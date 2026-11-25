import SwiftUI

struct SearchView: View {
    @Bindable var store: AionStore
    let onOpenConversation: (UUID) -> Void

    @State private var query: String = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var matchingConversations: [AionConversation] {
        guard !trimmedQuery.isEmpty else { return store.conversations }
        return store.conversations.filter { convo in
            convo.title.lowercased().contains(trimmedQuery) ||
            convo.messages.contains { $0.content.lowercased().contains(trimmedQuery) }
        }
    }

    private var matchingSkills: [AionSkill] {
        guard !trimmedQuery.isEmpty else { return [] }
        return store.skills.filter {
            $0.name.lowercased().contains(trimmedQuery) ||
            $0.summary.lowercased().contains(trimmedQuery) ||
            $0.id.lowercased().contains(trimmedQuery)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Search")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                // Liquid Glass Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AionTheme.inkSecondary)

                    TextField("Search threads, messages, skills...", text: $query)
                        .font(.system(size: 15.5))
                        .foregroundStyle(AionTheme.inkPrimary)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in
                            store.performRemoteSearch(keyword: newValue)
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AionTheme.inkTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 10)

                // Remote Full-Text Message Hits from AionUi Server
                if !store.remoteSearchHits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Server Message Matches")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AionTheme.inkSecondary)
                            .padding(.leading, 4)

                        ForEach(store.remoteSearchHits) { hit in
                            Button {
                                AionHaptics.selection()
                                if let existing = store.conversation(forRemoteID: hit.conversationRemoteID) {
                                    onOpenConversation(existing.id)
                                } else {
                                    let placeholder = AionConversation(
                                        remoteID: hit.conversationRemoteID,
                                        title: hit.conversationTitle,
                                        updatedAt: hit.createdAt,
                                        messages: [],
                                        hasLoadedMessages: false
                                    )
                                    store.conversations.insert(placeholder, at: 0)
                                    onOpenConversation(placeholder.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AionTheme.forest)
                                        .frame(width: 38, height: 38)
                                        .background(AionTheme.bentoSage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hit.conversationTitle)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AionTheme.inkPrimary)
                                            .lineLimit(1)
                                        Text(hit.previewText)
                                            .font(.system(size: 13))
                                            .foregroundStyle(AionTheme.inkSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(AionTheme.inkTertiary)
                                }
                                .padding(14)
                                .aionBentoCard(fill: AionTheme.surface, cornerRadius: 18)
                            }
                            .buttonStyle(AionSpringButtonStyle(scale: 0.985))
                        }
                    }
                }

                // Matching Skills
                if !matchingSkills.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Skills")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AionTheme.inkSecondary)
                            .padding(.leading, 4)

                        ForEach(matchingSkills) { skill in
                            Button {
                                AionHaptics.light()
                                let convo = store.createNewConversation(
                                    title: skill.name,
                                    initialPrompt: skill.samplePrompt,
                                    skill: skill
                                )
                                onOpenConversation(convo.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: skill.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AionTheme.lavenderAccent)
                                        .frame(width: 38, height: 38)
                                        .background(AionTheme.bentoLavender, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AionTheme.inkPrimary)
                                        Text(skill.summary)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(AionTheme.inkSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(AionTheme.inkTertiary)
                                }
                                .padding(14)
                                .aionBentoCard(fill: AionTheme.surface, cornerRadius: 18)
                            }
                            .buttonStyle(AionSpringButtonStyle(scale: 0.98))
                        }
                    }
                }

                // Matching Threads
                VStack(alignment: .leading, spacing: 10) {
                    Text(trimmedQuery.isEmpty ? "All Threads" : "Matching Threads")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AionTheme.inkSecondary)
                        .padding(.leading, 4)

                    if matchingConversations.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(AionTheme.inkTertiary)
                            Text("No matches for \"\(query)\"")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AionTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 38)
                        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(matchingConversations) { convo in
                                Button {
                                    AionHaptics.selection()
                                    onOpenConversation(convo.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: convo.iconName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AionTheme.terracotta)
                                            .frame(width: 38, height: 38)
                                            .background(AionTheme.bentoSand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(convo.title)
                                                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                                                .foregroundStyle(AionTheme.inkPrimary)
                                                .lineLimit(1)
                                            Text(convo.previewText)
                                                .font(.system(size: 13))
                                                .foregroundStyle(AionTheme.inkSecondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(AionTheme.inkTertiary)
                                    }
                                    .padding(14)
                                    .aionBentoCard(fill: AionTheme.surface, cornerRadius: 20)
                                }
                                .buttonStyle(AionSpringButtonStyle(scale: 0.985))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 108)
        }
    }
}
