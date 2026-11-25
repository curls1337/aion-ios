import SwiftUI

struct SettingsView: View {
    @Bindable var store: AionStore
    @State private var isTestingConnection = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                appearanceCard
                serverConnectionCard
                defaultModelCard
                aboutCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 108)
        }
    }

    // MARK: - Appearance (Warm Light / Obsidian Dark / System)

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Appearance & Liquid Glass", systemImage: "paintpalette.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)

            HStack(spacing: 10) {
                ForEach(AionAppearanceMode.allCases) { mode in
                    let isSelected = store.appearanceMode == mode
                    Button {
                        AionHaptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.appearanceMode = mode
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isSelected ? AionTheme.terracotta : AionTheme.inkSecondary)

                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? AionTheme.inkPrimary : AionTheme.inkSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            isSelected ? AionTheme.bentoSand : AionTheme.surfaceSecondary.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? AionTheme.terracotta.opacity(0.65) : .clear, lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(AionSpringButtonStyle(scale: 0.96))
                }
            }
        }
        .padding(18)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
    }

    // MARK: - API Server Connection Card

    private var serverConnectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Aion API Connection", systemImage: "network")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)

                Spacer()

                Text(store.connectionState.badgeLabel)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.connectionState.isHealthy ? AionTheme.forest : AionTheme.terracotta)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (store.connectionState.isHealthy ? AionTheme.bentoSage : AionTheme.bentoSand).opacity(0.85),
                        in: Capsule()
                    )
            }

            // Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AionTheme.inkSecondary)

                Picker("Backend Mode", selection: $store.serverConfig.mode) {
                    ForEach(AionBackendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.serverConfig.mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(AionTheme.inkTertiary)
            }

            if store.serverConfig.mode != .demo {
                VStack(alignment: .leading, spacing: 12) {
                    styledField(
                        title: "Server URL",
                        placeholder: store.serverConfig.mode == .aionWebUI
                            ? "https://aion.5nod.com"
                            : "https://api.openai.com/v1",
                        text: $store.serverConfig.baseURL
                    )

                    if store.serverConfig.mode == .aionWebUI {
                        styledField(title: "Username", placeholder: "admin", text: $store.serverConfig.username)
                        styledSecureField(title: "WebUI Password", placeholder: "Enter password", text: $store.serverConfig.password)
                    } else {
                        styledSecureField(title: "API Key / Bearer Token", placeholder: "sk-...", text: $store.serverConfig.apiKey)
                        styledField(title: "Model Name", placeholder: "gpt-4o / gemini-2.5-pro", text: $store.serverConfig.customModelName)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    AionHaptics.medium()
                    isTestingConnection = true
                    Task {
                        if store.serverConfig.mode == .aionWebUI && !store.serverConfig.password.isEmpty {
                            await store.signIn(
                                serverURL: store.serverConfig.baseURL,
                                username: store.serverConfig.username,
                                password: store.serverConfig.password
                            )
                        } else {
                            await store.refreshConnection()
                        }
                        isTestingConnection = false
                        if store.connectionState.isHealthy {
                            AionHaptics.success()
                        } else {
                            AionHaptics.warning()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                        }
                        Text(isTestingConnection ? "Connecting..." : (store.serverConfig.mode == .aionWebUI ? "Sign In & Sync" : "Test Connection"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AionTheme.terracotta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(AionSpringButtonStyle(scale: 0.97))

                if store.serverConfig.mode == .aionWebUI && store.currentUser != nil {
                    Button {
                        Task { await store.signOut() }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AionTheme.terracotta)
                            .frame(width: 48, height: 46)
                            .background(AionTheme.bentoSand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(AionSpringButtonStyle(scale: 0.95))
                    .accessibilityLabel("Sign Out")
                }
            }

            if case .offline(let reason) = store.connectionState {
                Text("Last error: \(reason)")
                    .font(.caption)
                    .foregroundStyle(AionTheme.terracotta)
            }

            if store.serverConfig.mode == .aionWebUI {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip: Run AionUi on your host with:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AionTheme.inkSecondary)
                    Text("AionUi --webui --remote")
                        .font(.caption.monospaced())
                        .foregroundStyle(AionTheme.forest)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AionTheme.surfaceSecondary.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
    }

    // MARK: - Default Model Card

    private var defaultModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Default Model", systemImage: "cpu.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)

            ForEach(AionModelOption.defaults) { model in
                let isSelected = store.selectedModelID == model.id
                Button {
                    store.selectedModelID = model.id
                    AionHaptics.selection()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)
                            Text(model.provider)
                                .font(.caption)
                                .foregroundStyle(AionTheme.inkSecondary)
                        }

                        Spacer()

                        Text(model.badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AionTheme.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AionTheme.surfaceSecondary, in: Capsule())

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? AionTheme.terracotta : AionTheme.inkTertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aion Native for iOS")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AionTheme.inkPrimary)
            Text("Warm Modern Bento · Adaptive Light & Dark · Apple Liquid Glass")
                .font(.caption)
                .foregroundStyle(AionTheme.inkSecondary)
            Text("Built with 100% pure SwiftUI (Swift 6) — zero external dependencies.")
                .font(.caption2)
                .foregroundStyle(AionTheme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)
    }

    // MARK: - Styled Inputs

    private func styledField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AionTheme.inkSecondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 14.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AionTheme.surfaceSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func styledSecureField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AionTheme.inkSecondary)

            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AionTheme.surfaceSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
