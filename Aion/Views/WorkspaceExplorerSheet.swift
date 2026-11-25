import SwiftUI

struct WorkspaceExplorerSheet: View {
    @Bindable var store: AionStore
    let conversationID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: String = ""
    @State private var pathStack: [String] = []
    @State private var files: [AionWorkspaceFile] = []
    @State private var isLoading = true
    @State private var previewFile: (name: String, content: String)?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading workspace files...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if files.isEmpty {
                    ContentUnavailableView(
                        "Workspace Empty",
                        systemImage: "folder",
                        description: Text("No files found in this conversation workspace.")
                    )
                } else {
                    List {
                        if !pathStack.isEmpty {
                            Button {
                                currentPath = pathStack.removeLast()
                                Task { await reload() }
                            } label: {
                                Label("Up one folder", systemImage: "arrow.turn.up.left")
                                    .foregroundStyle(AionTheme.terracotta)
                            }
                        }

                        ForEach(files) { file in
                            Button {
                                if file.isDirectory {
                                    pathStack.append(currentPath)
                                    currentPath = file.path
                                    Task { await reload() }
                                } else {
                                    Task {
                                        let content = await store.readWorkspaceFileContent(path: file.path)
                                        previewFile = (file.name, content.isEmpty ? "(Binary or empty file)" : content)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text.fill")
                                        .foregroundStyle(file.isDirectory ? AionTheme.amber : AionTheme.terracotta)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(AionTheme.inkPrimary)
                                        if let bytes = file.sizeBytes, !file.isDirectory {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                                .font(.caption)
                                                .foregroundStyle(AionTheme.inkSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(AionTheme.inkTertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentPath.isEmpty ? "Workspace Files" : (currentPath as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .sheet(isPresented: Binding(
                get: { previewFile != nil },
                set: { if !$0 { previewFile = nil } }
            )) {
                if let file = previewFile {
                    NavigationStack {
                        ScrollView {
                            Text(file.content)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }
                        .navigationTitle(file.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { previewFile = nil }
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        files = await store.fetchWorkspaceFiles(for: conversationID, subPath: currentPath)
        isLoading = false
    }
}
