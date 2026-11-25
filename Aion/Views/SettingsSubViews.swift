import SwiftUI

// MARK: - 1. Assistants & Rules Manager

struct AssistantsManagerView: View {
    @Bindable var store: AionStore
    @State private var editingAssistant: AionAssistant?

    var body: some View {
        List {
            if store.assistants.isEmpty {
                ContentUnavailableView(
                    "No Assistants Loaded",
                    systemImage: "person.2.slash",
                    description: Text("Sign in to AionUi Remote and pull to refresh.")
                )
            } else {
                ForEach(store.assistants) { assistant in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AionTheme.bentoSand)
                                .frame(width: 40, height: 40)
                            Image(systemName: "sparkles")
                                .foregroundStyle(AionTheme.terracotta)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(assistant.name)
                                    .font(.headline)
                                if store.selectedAssistant?.id == assistant.id {
                                    Text("Active")
                                        .font(.caption2.bold())
                                        .foregroundStyle(AionTheme.forest)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AionTheme.bentoSage, in: Capsule())
                                }
                            }
                            let label = store.cleanAgentLabel(for: assistant)
                            if !label.isEmpty {
                                Text(label)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if !assistant.description.isEmpty {
                                Text(assistant.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { assistant.enabled },
                            set: { _ in Task { await store.toggleAssistant(assistant) } }
                        ))
                        .labelsHidden()
                        .tint(AionTheme.forest)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedAssistantID = assistant.id
                        AionHaptics.selection()
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            editingAssistant = assistant
                        } label: {
                            Label("Rules", systemImage: "doc.text")
                        }
                        .tint(AionTheme.lavenderAccent)
                    }
                    .contextMenu {
                        Button {
                            store.selectedAssistantID = assistant.id
                            AionHaptics.selection()
                        } label: {
                            Label("Set as Active Assistant", systemImage: "checkmark.circle")
                        }
                        Button {
                            editingAssistant = assistant
                        } label: {
                            Label("Edit Assistant Rules", systemImage: "doc.text.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle("Assistants")
        .refreshable { await store.syncWorkspace() }
        .sheet(item: $editingAssistant) { assistant in
            AssistantRuleEditorSheet(store: store, assistant: assistant)
        }
    }
}

private struct AssistantRuleEditorSheet: View {
    @Bindable var store: AionStore
    let assistant: AionAssistant

    @Environment(\.dismiss) private var dismiss
    @State private var ruleText = ""
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading rules...")
                } else {
                    TextEditor(text: $ruleText)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(12)
                }
            }
            .navigationTitle("\(assistant.name) Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        isSaving = true
                        Task {
                            let ok = await store.saveAssistantRule(assistant.id, content: ruleText)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(isSaving || isLoading)
                }
            }
            .task {
                ruleText = await store.loadAssistantRule(assistant.id)
                isLoading = false
            }
        }
    }
}

// MARK: - 2. Managed Agents View

struct ManagedAgentsView: View {
    @Bindable var store: AionStore
    @State private var checkingID: String?

    var body: some View {
        List {
            if store.managedAgents.isEmpty {
                ContentUnavailableView(
                    "No Agents Found",
                    systemImage: "cpu",
                    description: Text("Pull down to sync agents from your AionUi host.")
                )
            } else {
                ForEach(store.managedAgents) { agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.backend)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { agent.enabled },
                                set: { _ in Task { await store.toggleManagedAgent(agent) } }
                            ))
                            .labelsHidden()
                            .tint(AionTheme.forest)
                        }

                        if let cmd = agent.command, !cmd.isEmpty {
                            Text(cmd)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack {
                            if let status = agent.healthStatus, !status.isEmpty {
                                Text(status)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AionTheme.forest)
                            } else {
                                Text(agent.installed ? "Installed" : "Not detected")
                                    .font(.caption)
                                    .foregroundStyle(agent.installed ? AionTheme.forest : AionTheme.terracotta)
                            }

                            Spacer()

                            Button {
                                checkingID = agent.id
                                Task {
                                    await store.healthCheckAgent(agent)
                                    checkingID = nil
                                }
                            } label: {
                                if checkingID == agent.id {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Label("Health Check", systemImage: "stethoscope")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Managed Agents")
        .refreshable { await store.syncWorkspace() }
    }
}

// MARK: - 3. Model Providers View

struct ProvidersListView: View {
    @Bindable var store: AionStore

    var body: some View {
        List {
            if store.providers.isEmpty {
                ContentUnavailableView(
                    "No Providers Synced",
                    systemImage: "server.rack",
                    description: Text("Providers configured on your AionUi host appear here.")
                )
            } else {
                ForEach(store.providers) { provider in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(provider.name)
                                .font(.headline)
                            Spacer()
                            Text(provider.platform)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AionTheme.bentoSand, in: Capsule())
                        }
                        if !provider.baseURL.isEmpty {
                            Text(provider.baseURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !provider.models.isEmpty {
                            Text("Models: \(provider.models.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Text(provider.hasAPIKey ? "API Key configured" : "No API Key set")
                            .font(.caption2)
                            .foregroundStyle(provider.hasAPIKey ? AionTheme.forest : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Model Providers")
        .refreshable { await store.syncWorkspace() }
    }
}

// MARK: - 4. MCP Servers Manager

struct MCPServersManagerView: View {
    @Bindable var store: AionStore

    var body: some View {
        List {
            if store.mcpServers.isEmpty {
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "puzzlepiece.extension",
                    description: Text("MCP servers from your AionUi host will appear here.")
                )
            } else {
                ForEach(store.mcpServers) { server in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                    .font(.headline)
                                Text(server.transportType.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AionTheme.bentoLavender, in: Capsule())
                            }
                            if !server.endpointOrCommand.isEmpty {
                                Text(server.endpointOrCommand)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.enabled },
                            set: { _ in Task { await store.toggleMCPServer(server) } }
                        ))
                        .labelsHidden()
                        .tint(AionTheme.forest)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.deleteMCPServer(server) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("MCP Servers")
        .refreshable { await store.syncWorkspace() }
    }
}

// MARK: - 5. General Server Settings (Synced via GET/PATCH /api/settings)

struct RemotePreferencesView: View {
    @Bindable var store: AionStore
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Server Preferences (/api/settings)") {
                Picker("Language", selection: $store.remoteSettings.language) {
                    Text("English (en-US)").tag("en-US")
                    Text("Bahasa Indonesia (id-ID)").tag("id-ID")
                    Text("Chinese (zh-CN)").tag("zh-CN")
                    Text("Japanese (ja-JP)").tag("ja-JP")
                }

                Toggle("Enable Notifications", isOn: $store.remoteSettings.notificationEnabled)
                Toggle("Cron Task Notifications", isOn: $store.remoteSettings.cronNotificationEnabled)
                Toggle("Command Queue Enabled", isOn: $store.remoteSettings.commandQueueEnabled)
                Toggle("Save Uploads to Workspace", isOn: $store.remoteSettings.saveUploadToWorkspace)
            }

            Section {
                Button {
                    isSaving = true
                    Task {
                        await store.saveRemoteSettings()
                        isSaving = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSaving ? "Saving to Server..." : "Save Preferences to AionUi")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSaving || store.serverConfig.mode != .aionWebUI)
            }

            if !store.systemInfo.version.isEmpty || !store.systemInfo.platform.isEmpty {
                Section("Host System Info") {
                    if !store.systemInfo.version.isEmpty {
                        LabeledContent("AionUi Version", value: store.systemInfo.version)
                    }
                    if !store.systemInfo.platform.isEmpty {
                        LabeledContent("Platform", value: "\(store.systemInfo.platform) \(store.systemInfo.arch)")
                    }
                    if !store.systemInfo.hostname.isEmpty {
                        LabeledContent("Hostname", value: store.systemInfo.hostname)
                    }
                }
            }
        }
        .navigationTitle("Server Settings")
        .refreshable { await store.syncWorkspace() }
    }
}
