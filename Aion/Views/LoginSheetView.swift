import SwiftUI

struct LoginSheetView: View {
    @Bindable var store: AionStore
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AionAmbientCanvas()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Brand Emblem
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(AionTheme.bentoSand)
                                    .frame(width: 72, height: 72)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(AionTheme.terracotta)
                            }
                            .aionLiquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, shadowRadius: 16)

                            Text("Sign in to Aion")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)

                            Text("Connect directly to your live AionUi server for real agents, threads, skills, and cron jobs.")
                                .font(.system(size: 14.5))
                                .foregroundStyle(AionTheme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .padding(.top, 20)

                        // Credentials Card
                        VStack(alignment: .leading, spacing: 14) {
                            inputRow(title: "Server URL", icon: "globe", placeholder: "https://aion.5nod.com", text: $serverURL, isSecure: false, isURL: true)
                            inputRow(title: "Username", icon: "person.fill", placeholder: "admin", text: $username, isSecure: false, isURL: false)
                            inputRow(title: "Password", icon: "lock.fill", placeholder: "Enter your AionUi password", text: $password, isSecure: true, isURL: false)

                            if let error = store.loginErrorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(AionTheme.terracotta)
                                    Text(error)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AionTheme.terracotta)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AionTheme.bentoSand.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button {
                                AionHaptics.medium()
                                Task {
                                    await store.signIn(serverURL: serverURL, username: username, password: password)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if store.isSigningIn {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    Text(store.isSigningIn ? "Signing In..." : "Connect & Sign In")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AionTheme.terracotta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .disabled(store.isSigningIn || serverURL.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                            .opacity((store.isSigningIn || password.isEmpty) ? 0.65 : 1)
                            .buttonStyle(AionSpringButtonStyle(scale: 0.97))
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .aionBentoCard(fill: AionTheme.surface, cornerRadius: AionTheme.cardRadius)

                        // Optional offline Demo button
                        Button {
                            store.switchToDemoMode()
                            dismiss()
                        } label: {
                            Text("Preview Offline Demo Instead")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AionTheme.inkSecondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 6)
                        }
                        .buttonStyle(AionSpringButtonStyle())
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
            }
            .onAppear {
                serverURL = store.serverConfig.baseURL.isEmpty ? "https://aion.5nod.com" : store.serverConfig.baseURL
                username = store.serverConfig.username.isEmpty ? "admin" : store.serverConfig.username
                password = store.serverConfig.password
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.currentUser != nil || store.serverConfig.mode == .demo {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
    }

    private func inputRow(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        isURL: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AionTheme.inkSecondary)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AionTheme.inkTertiary)
                    .frame(width: 20)

                if isSecure {
                    SecureField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(isURL ? .URL : .default)
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AionTheme.surfaceSecondary.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
