import SwiftUI

struct BentoDashboardView: View {
    @Bindable var store: AionStore
    let onOpenConversation: (UUID) -> Void
    let onOpenScheduledTasks: () -> Void
    let onOpenSkills: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pulseDot = false
    @State private var renamingConversation: AionConversation?
    @State private var renameDraft: String = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                bentoGridSection
                recentThreadsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 108)
        }
        .refreshable {
            await store.refreshConnection()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseDot = true
            }
        }
        .alert("Rename Thread", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Thread title", text: $renameDraft)
            Button("Cancel", role: .cancel) { renamingConversation = nil }
            Button("Save") {
                if let convo = renamingConversation {
                    let title = renameDraft
                    renamingConversation = nil
                    Task { await store.renameConversation(convo.id, newTitle: title) }
                }
            }
        }
    }

    // MARK: - Greeting & Live API Pill

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(store.greetingTitle)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                Spacer()

                // Quick Light/Dark Mode Liquid Glass button
                Button {
                    AionHaptics.light()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        toggleQuickAppearance()
                    }
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AionTheme.inkPrimary)
                        .frame(width: 40, height: 40)
                        .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 8)
                }
                .buttonStyle(AionSpringButtonStyle())
                .accessibilityLabel("Toggle Light or Dark Mode")
            }

            // Live API Status Pill (Liquid Glass capsule)
            Button {
                AionHaptics.selection()
                if store.connectionState == .needsLogin {
                    store.isLoginSheetPresented = true
                } else {
                    store.selectedTab = .settings
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseDot && store.connectionState.isHealthy ? 1.2 : 0.9)

                    Text(store.connectionState.badgeLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AionTheme.inkPrimary.opacity(0.88))

                    if store.isWebSocketConnected {
                        Text("WS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AionTheme.forest)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AionTheme.bentoSage, in: Capsule())
                    } else if store.isSyncingWorkspace {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AionTheme.inkTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 8)
            }
            .buttonStyle(AionSpringButtonStyle(scale: 0.97))
        }
    }

    private var statusDotColor: Color {
        switch store.connectionState {
        case .connected, .demo:
            return AionTheme.forest
        case .connecting, .needsLogin:
            return AionTheme.amber
        case .offline:
            return AionTheme.terracotta
        }
    }

    private func toggleQuickAppearance() {
        switch store.appearanceMode {
        case .system:
            store.appearanceMode = (colorScheme == .dark) ? .light : .dark
        case .light:
            store.appearanceMode = .dark
        case .dark:
            store.appearanceMode = .light
        }
    }

    // MARK: - 2x2 Warm Modern Bento Grid

    private var bentoGridSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            // Card 1: New Chat (Warm Sand + Terracotta)
            BentoTileCard(
                fill: AionTheme.bentoSand,
                icon: "bubble.left.fill",
                iconTint: AionTheme.terracotta,
                title: "New Chat",
                subtitle: store.headerAssistantLabel
            ) {
                AionHaptics.medium()
                let convo = store.createNewConversation()
                onOpenConversation(convo.id)
            }

            // Card 2: Scheduled Tasks (Soft Sage + Forest)
            BentoTileCard(
                fill: AionTheme.bentoSage,
                icon: "clock.fill",
                iconTint: AionTheme.forest,
                title: "Scheduled\nTasks",
                subtitle: "\(store.activeCronCount) active"
            ) {
                AionHaptics.light()
                onOpenScheduledTasks()
            }

            // Card 3: Skills Library (Muted Lavender + Indigo)
            BentoTileCard(
                fill: AionTheme.bentoLavender,
                icon: "wand.and.stars",
                iconTint: AionTheme.lavenderAccent,
                title: "Skills Library",
                subtitle: "\(store.enabledSkillsCount) tools"
            ) {
                AionHaptics.light()
                onOpenSkills()
            }

            // Card 4: Voice Mode (Alabaster / Elevated Obsidian)
            BentoTileCard(
                fill: AionTheme.bentoAlabaster,
                icon: "waveform",
                iconTint: AionTheme.inkPrimary,
                title: "Voice Mode",
                subtitle: "Tap to speak"
            ) {
                AionHaptics.medium()
                store.isVoiceModePresented = true
            }
        }
    }

    // MARK: - Recent Threads Card

    private var recentThreadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Threads")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                Spacer()

                Text("\(store.conversations.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AionTheme.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AionTheme.surfaceSecondary, in: Capsule())
            }

            if store.conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(AionTheme.terracotta)
                    Text("No threads yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AionTheme.inkPrimary)
                    Text("Tap New Chat to start talking with Aion.")
                        .font(.caption)
                        .foregroundStyle(AionTheme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(store.conversations.enumerated()), id: \.element.id) { index, convo in
                        Button {
                            AionHaptics.selection()
                            onOpenConversation(convo.id)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(threadIconBackground(for: index))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: convo.iconName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(threadIconForeground(for: index))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(convo.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AionTheme.inkPrimary)
                                        .lineLimit(1)

                                    Text(convo.previewText)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AionTheme.inkSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Text(convo.updatedAt, style: .relative)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AionTheme.inkTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AionSpringButtonStyle(scale: 0.985))
                        .contextMenu {
                            Button {
                                renameDraft = convo.title
                                renamingConversation = convo
                            } label: {
                                Label("Rename Thread", systemImage: "pencil")
                            }
                            Button {
                                Task { await store.resetConversation(convo.id) }
                            } label: {
                                Label("Reset Messages", systemImage: "arrow.counterclockwise")
                            }
                            Button(role: .destructive) {
                                store.deleteConversation(convo.id)
                            } label: {
                                Label("Delete Thread", systemImage: "trash")
                            }
                        }

                        if index < store.conversations.count - 1 {
                            Divider()
                                .overlay(AionTheme.border)
                                .padding(.leading, 56)
                        }
                    }

                    if store.conversationsNextCursor != nil {
                        Button {
                            Task { await store.loadMoreConversations() }
                        } label: {
                            HStack(spacing: 8) {
                                if store.isLoadingMoreConversations {
                                    ProgressView().controlSize(.small)
                                }
                                Text(store.isLoadingMoreConversations ? "Loading..." : "Load Older Threads")
                                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AionTheme.terracotta)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .padding(18)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
    }

    private func threadIconBackground(for index: Int) -> Color {
        switch index % 3 {
        case 0: return AionTheme.bentoSand
        case 1: return AionTheme.bentoSage
        default: return AionTheme.bentoLavender
        }
    }

    private func threadIconForeground(for index: Int) -> Color {
        switch index % 3 {
        case 0: return AionTheme.terracotta
        case 1: return AionTheme.forest
        default: return AionTheme.lavenderAccent
        }
    }
}

// MARK: - Bento Tile Component

private struct BentoTileCard: View {
    let fill: Color
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconTint)
                }

                Spacer(minLength: 18)

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AionTheme.inkSecondary)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
            .padding(16)
            .aionBentoCard(fill: fill, cornerRadius: AionTheme.cardRadius)
        }
        .buttonStyle(AionSpringButtonStyle(scale: 0.96))
    }
}
