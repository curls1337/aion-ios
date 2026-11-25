import SwiftUI
import UniformTypeIdentifiers

struct FluidChatView: View {
    @Bindable var store: AionStore
    let conversationID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @State private var pendingAttachments: [AionAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isSkillPickerPresented = false
    @FocusState private var isComposerFocused: Bool

    private var conversation: AionConversation? {
        store.conversation(for: conversationID)
    }

    private var latestSuggestions: [String] {
        guard let last = conversation?.messages.last, last.role == .assistant else { return [] }
        return last.followUpSuggestions
    }

    var body: some View {
        ZStack {
            AionAmbientCanvas()

            VStack(spacing: 0) {
                chatMessageList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomComposerDock
        }
        .task(id: conversationID) {
            await store.loadMessagesIfNeeded(for: conversationID)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    AionHaptics.light()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AionTheme.inkPrimary)
                        .frame(width: 36, height: 36)
                        .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 6)
                }
            }

            ToolbarItem(placement: .principal) {
                modelPickerPill
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    AionHaptics.light()
                    store.isVoiceModePresented = true
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AionTheme.inkPrimary)
                        .frame(width: 36, height: 36)
                        .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 6)
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    pendingAttachments.append(
                        AionAttachment(fileName: url.lastPathComponent, sizeLabel: formattedSize)
                    )
                }
                AionHaptics.selection()
            }
        }
        .sheet(isPresented: $isSkillPickerPresented) {
            SkillQuickPickerSheet(
                skills: store.skills.filter(\.isEnabled),
                selectedSkill: store.selectedSkillForNextPrompt
            ) { skill in
                store.selectedSkillForNextPrompt = skill
                isSkillPickerPresented = false
                AionHaptics.selection()
            }
            .presentationDetents([.medium])
            .presentationCornerRadius(28)
        }
    }

    // MARK: - Top Model Switcher Pill

    private var modelPickerPill: some View {
        Menu {
            if store.serverConfig.mode == .aionWebUI && !store.assistants.isEmpty {
                Section("Aion Assistants") {
                    ForEach(store.assistants) { assistant in
                        Button {
                            store.selectedAssistantID = assistant.id
                            AionHaptics.selection()
                        } label: {
                            Label(
                                "\(assistant.name) · \(assistant.backend)",
                                systemImage: store.selectedAssistant?.id == assistant.id ? "checkmark" : "sparkles"
                            )
                        }
                    }
                }
            } else {
                ForEach(AionModelOption.defaults) { option in
                    Button {
                        store.selectedModelID = option.id
                        AionHaptics.selection()
                    } label: {
                        Label(
                            "\(option.displayName) · \(option.provider)",
                            systemImage: store.selectedModelID == option.id ? "checkmark" : "sparkles"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Aion")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                Text("·")
                    .foregroundStyle(AionTheme.inkTertiary)

                Text(store.headerAssistantLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AionTheme.inkSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AionTheme.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 6)
        }
    }

    // MARK: - Editorial Message Feed

    private var chatMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let messages = conversation?.messages, !messages.isEmpty {
                        ForEach(messages) { message in
                            EditorialMessageRow(message: message, isStreaming: store.isStreaming && message.id == messages.last?.id)
                                .id(message.id)
                        }
                    } else if store.isLoadingMessages {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(AionTheme.terracotta)
                            Text("Loading conversation from Aion...")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(AionTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        emptyThreadStarter
                    }

                    Color.clear
                        .frame(height: 12)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation?.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            .onChange(of: conversation?.messages.last?.content) { _, _ in
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    private var emptyThreadStarter: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 36)

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AionTheme.terracotta)
                .frame(width: 54, height: 54)
                .aionBentoCard(fill: AionTheme.bentoSand, cornerRadius: 18)

            Text("What can Aion help you build today?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)

            Text("Connected in \(store.serverConfig.mode.rawValue). Pick a quick prompt or ask anything below.")
                .font(.system(size: 15))
                .foregroundStyle(AionTheme.inkSecondary)

            VStack(spacing: 10) {
                starterPromptRow("Summarize the Q3 report", icon: "doc.text.fill")
                starterPromptRow("Show Swift WebSocket connection code", icon: "chevron.left.forwardslash.chevron.right")
                starterPromptRow("Review my active scheduled tasks", icon: "clock.fill")
            }
            .padding(.top, 4)
        }
    }

    private func starterPromptRow(_ prompt: String, icon: String) -> some View {
        Button {
            store.sendMessage(prompt, in: conversationID)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AionTheme.terracotta)
                    .frame(width: 28, height: 28)
                    .background(AionTheme.bentoSand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(prompt)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AionTheme.inkPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AionTheme.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .aionBentoCard(fill: AionTheme.surface, cornerRadius: 16)
        }
        .buttonStyle(AionSpringButtonStyle(scale: 0.98))
    }

    // MARK: - Floating Liquid Glass Bottom Composer & Suggestions

    private var bottomComposerDock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pending attachments or selected skill chips
            if !pendingAttachments.isEmpty || store.selectedSkillForNextPrompt != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let skill = store.selectedSkillForNextPrompt {
                            HStack(spacing: 6) {
                                Image(systemName: skill.iconName)
                                    .font(.caption.weight(.semibold))
                                Text("Skill: \(skill.name)")
                                    .font(.caption.weight(.semibold))
                                Button {
                                    store.selectedSkillForNextPrompt = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(AionTheme.lavenderAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .aionLiquidGlass(in: Capsule(), tint: AionTheme.lavenderAccent, interactive: true, shadowRadius: 4)
                        }

                        ForEach(pendingAttachments) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.caption)
                                    .foregroundStyle(AionTheme.terracotta)
                                Text(file.fileName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AionTheme.inkPrimary)
                                    .lineLimit(1)
                                Button {
                                    pendingAttachments.removeAll(where: { $0.id == file.id })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(AionTheme.inkSecondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Quick Follow-up Suggestion Pills (Concept 3 style)
            if !latestSuggestions.isEmpty && !store.isStreaming {
                ScrollView(.horizontal, showsIndicators: false) {
                    AionGlassContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(latestSuggestions, id: \.self) { suggestion in
                                Button {
                                    store.sendMessage(suggestion, in: conversationID)
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AionTheme.inkPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 6)
                                }
                                .buttonStyle(AionSpringButtonStyle(scale: 0.95))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            // Main Tactile Liquid Glass Composer Bar
            AionGlassContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    // + Attachment Circle Glass Button
                    Button {
                        AionHaptics.light()
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .frame(width: 42, height: 42)
                            .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 8)
                    }
                    .buttonStyle(AionSpringButtonStyle())

                    // Sparkle Skills Quick Picker Button
                    Button {
                        AionHaptics.light()
                        isSkillPickerPresented = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                store.selectedSkillForNextPrompt != nil ? AionTheme.lavenderAccent : AionTheme.inkPrimary
                            )
                            .frame(width: 42, height: 42)
                            .aionLiquidGlass(
                                in: Circle(),
                                tint: store.selectedSkillForNextPrompt != nil ? AionTheme.lavenderAccent : nil,
                                interactive: true,
                                shadowRadius: 8
                            )
                    }
                    .buttonStyle(AionSpringButtonStyle())

                    // Glass Pill Text Field + Terracotta Send Button
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask Aion...", text: $inputText, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .lineLimit(1...5)
                            .focused($isComposerFocused)
                            .padding(.leading, 14)
                            .padding(.vertical, 10)

                        Button {
                            if store.isStreaming {
                                store.stopStreaming(in: conversationID)
                                AionHaptics.light()
                            } else {
                                sendCurrentInput()
                            }
                        } label: {
                            Image(systemName: store.isStreaming ? "stop.fill" : "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    (store.isStreaming || canSend) ? AionTheme.terracotta : AionTheme.inkTertiary.opacity(0.45),
                                    in: Circle()
                                )
                        }
                        .disabled(!store.isStreaming && !canSend)
                        .padding(4)
                        .buttonStyle(AionSpringButtonStyle(scale: 0.92))
                    }
                    .aionLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true, shadowRadius: 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .padding(.top, 2)
            }
        }
        .background(
            LinearGradient(
                colors: [AionTheme.canvas.opacity(0), AionTheme.canvas.opacity(0.82), AionTheme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendCurrentInput() {
        let prompt = inputText
        let files = pendingAttachments
        inputText = ""
        pendingAttachments = []
        isComposerFocused = false
        store.sendMessage(prompt, attachments: files, in: conversationID)
    }
}

// MARK: - Editorial Message Row (Concept 3 Fluid Layout)

private struct EditorialMessageRow: View {
    let message: AionMessage
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .user {
                // Clean right-aligned editorial prompt (no heavy blue bubble)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.content)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AionTheme.inkPrimary)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AionTheme.surfaceSecondary.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !message.attachments.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(message.attachments) { file in
                                FileChipView(fileName: file.fileName)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Collapsible Thinking / Reasoning block
                if let thinking = message.thinking, !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.system(size: 13))
                            .foregroundStyle(AionTheme.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Label("Reasoning", systemImage: "brain.head.profile")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(AionTheme.inkSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AionTheme.surfaceSecondary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Tool / Skill Execution Pills
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls) { tool in
                            ToolExecutionPill(tool: tool)
                        }
                    }
                }

                // Airy full-width editorial markdown body
                if !message.content.isEmpty {
                    AionMarkdownView(text: message.content)
                } else if isStreaming {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AionTheme.terracotta)
                        Text("Aion is thinking...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AionTheme.inkSecondary)
                    }
                    .padding(.vertical, 4)
                }

                // Executive Summary / Interactive Card (Concept 3 signature)
                if let card = message.summaryCard {
                    SummaryCardView(card: card)
                }
            }
        }
    }
}

private struct ToolExecutionPill: View {
    let tool: AionToolCall

    var body: some View {
        HStack(spacing: 8) {
            if tool.status == .running {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AionTheme.forest)
            } else {
                Image(systemName: tool.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tool.status == .completed ? AionTheme.forest : AionTheme.terracotta)
            }

            Text(tool.name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AionTheme.inkPrimary)

            Text("· \(tool.detail)")
                .font(.system(size: 12))
                .foregroundStyle(AionTheme.inkSecondary)
                .lineLimit(1)

            if let duration = tool.durationSeconds {
                Text(String(format: "%.1fs", duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AionTheme.inkTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .aionLiquidGlass(in: Capsule(), interactive: false, shadowRadius: 4)
    }
}

private struct SummaryCardView: View {
    let card: AionSummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AionTheme.terracotta)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(bullet)
                            .font(.system(size: 14.5))
                            .foregroundStyle(AionTheme.inkPrimary.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let fileName = card.attachmentName {
                FileChipView(fileName: fileName)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: 20)
    }
}

private struct FileChipView: View {
    let fileName: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 13))
                .foregroundStyle(AionTheme.terracotta)

            Text(fileName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AionTheme.fileChipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AionTheme.border, lineWidth: 0.75)
        )
    }
}

private struct SkillQuickPickerSheet: View {
    let skills: [AionSkill]
    let selectedSkill: AionSkill?
    let onSelect: (AionSkill?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if selectedSkill != nil {
                    Button(role: .destructive) {
                        onSelect(nil)
                    } label: {
                        Label("Clear Selected Skill", systemImage: "xmark.circle")
                    }
                }

                ForEach(skills) { skill in
                    Button {
                        onSelect(skill)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: skill.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AionTheme.lavenderAccent)
                                .frame(width: 34, height: 34)
                                .background(AionTheme.bentoLavender, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.headline)
                                    .foregroundStyle(AionTheme.inkPrimary)
                                Text(skill.summary)
                                    .font(.caption)
                                    .foregroundStyle(AionTheme.inkSecondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if selectedSkill?.id == skill.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AionTheme.forest)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Run with Skill")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
