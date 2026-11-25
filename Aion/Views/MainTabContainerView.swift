import SwiftUI

struct MainTabContainerView: View {
    @Bindable var store: AionStore
    @State private var navigationPath: [UUID] = []
    @State private var showWorkspaceSection: WorkspaceSegment = .skills
    @Namespace private var dockNamespace

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                AionAmbientCanvas()

                Group {
                    switch store.selectedTab {
                    case .home:
                        BentoDashboardView(
                            store: store,
                            onOpenConversation: { id in
                                navigationPath.append(id)
                            },
                            onOpenScheduledTasks: {
                                showWorkspaceSection = .tasks
                                store.selectedTab = .workspace
                            },
                            onOpenSkills: {
                                showWorkspaceSection = .skills
                                store.selectedTab = .workspace
                            }
                        )
                    case .search:
                        SearchView(store: store) { id in
                            navigationPath.append(id)
                        }
                    case .workspace:
                        SkillsAndTasksView(
                            store: store,
                            selectedSegment: $showWorkspaceSection,
                            onLaunchConversation: { id in
                                navigationPath.append(id)
                            }
                        )
                    case .settings:
                        SettingsView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Liquid Glass Pill Dock (Concept 3 signature)
                floatingLiquidGlassDock
                    .padding(.horizontal, 26)
                    .padding(.bottom, 10)
            }
            .navigationDestination(for: UUID.self) { conversationID in
                FluidChatView(store: store, conversationID: conversationID)
            }
            .fullScreenCover(isPresented: $store.isVoiceModePresented) {
                VoiceModeView(store: store) { spokenPrompt in
                    store.isVoiceModePresented = false
                    let convo = store.createNewConversation(
                        title: String(spokenPrompt.prefix(34)),
                        initialPrompt: spokenPrompt
                    )
                    navigationPath.append(convo.id)
                }
            }
        }
    }

    private var floatingLiquidGlassDock: some View {
        AionGlassContainer(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(AionTab.allCases) { tab in
                    let isSelected = store.selectedTab == tab
                    Button {
                        guard store.selectedTab != tab else { return }
                        AionHaptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            store.selectedTab = tab
                        }
                    } label: {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(AionTheme.terracotta.opacity(0.18))
                                    .matchedGeometryEffect(id: "dock-pill", in: dockNamespace)
                            }
                            Image(systemName: tab.iconName)
                                .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AionTheme.terracotta : AionTheme.inkPrimary.opacity(0.75))
                                .symbolEffect(.bounce, value: isSelected)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(AionSpringButtonStyle(scale: 0.94))
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 18)
        }
    }
}
