import SwiftUI

struct VoiceModeView: View {
    @Bindable var store: AionStore
    let onSubmitTranscript: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var speech = AionSpeechService()
    @State private var breathe = false

    var body: some View {
        ZStack {
            AionAmbientCanvas()

            VStack(spacing: 24) {
                // Top bar
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(speech.isRecording ? AionTheme.terracotta : AionTheme.forest)
                            .frame(width: 8, height: 8)
                        Text(speech.isRecording ? "Listening..." : "Aion Voice Mode")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AionTheme.inkPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .aionLiquidGlass(in: Capsule(), interactive: false, shadowRadius: 8)

                    Spacer()

                    Button {
                        speech.stopRecording()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .frame(width: 40, height: 40)
                            .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 8)
                    }
                    .buttonStyle(AionSpringButtonStyle())
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                Spacer()

                // Organic Liquid Glass Reactive Voice Orb
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AionTheme.terracotta.opacity(0.35), AionTheme.forest.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 30,
                                endRadius: 150
                            )
                        )
                        .frame(width: 250, height: 250)
                        .scaleEffect(speech.isRecording ? (0.95 + speech.audioLevel * 0.45) : (breathe ? 1.08 : 0.94))
                        .animation(
                            .easeInOut(duration: speech.isRecording ? 0.14 : 2.2),
                            value: speech.isRecording ? speech.audioLevel : CGFloat(breathe ? 1.0 : 0.0)
                        )

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AionTheme.terracotta.opacity(0.65), AionTheme.forest.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 144, height: 144)
                        .blur(radius: 18)

                    Button {
                        speech.toggleRecording()
                    } label: {
                        Image(systemName: speech.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(AionTheme.inkPrimary)
                            .frame(width: 132, height: 132)
                            .aionLiquidGlass(
                                in: Circle(),
                                tint: speech.isRecording ? AionTheme.terracotta : nil,
                                interactive: true,
                                shadowRadius: 20
                            )
                    }
                    .buttonStyle(AionSpringButtonStyle(scale: 0.94))
                }

                // Editable Live Transcript / Status Card
                VStack(spacing: 10) {
                    if let statusMessage = speech.statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AionTheme.terracotta)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AionTheme.bentoSand.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    TextField(
                        speech.isRecording ? "Mendengarkan suara Anda..." : "Ketuk mikrofon atau ketik langsung di sini...",
                        text: $speech.transcript,
                        axis: .vertical
                    )
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AionTheme.inkPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .aionLiquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, shadowRadius: 10)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Action Bar
                AionGlassContainer(spacing: 14) {
                    HStack(spacing: 14) {
                        Button {
                            speech.toggleRecording()
                        } label: {
                            Label(speech.isRecording ? "Stop" : "Speak", systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 12)
                        }
                        .buttonStyle(AionSpringButtonStyle())

                        if !speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                let finalPrompt = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                speech.stopRecording()
                                AionHaptics.success()
                                onSubmitTranscript(finalPrompt)
                            } label: {
                                Label("Send", systemImage: "arrow.up.circle.fill")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .background(AionTheme.terracotta, in: Capsule())
                                    .shadow(color: AionTheme.terracotta.opacity(0.35), radius: 12, y: 6)
                            }
                            .buttonStyle(AionSpringButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onDisappear {
            speech.stopRecording()
        }
    }
}
