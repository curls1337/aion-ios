import SwiftUI

/// Adaptive Liquid Glass Container:
/// Uses native iOS 26 `GlassEffectContainer` when built with iOS 26 SDK & running on iOS 26+,
/// and seamlessly falls back to a clean layout group on iOS 17–18.
struct AionGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// Native iOS 26 Liquid Glass modifier with high-craft specular glass fallback for iOS 17–18.
struct AionLiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let shadowRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            nativeLiquidGlass(content)
        } else {
            fallbackLiquidGlass(content)
        }
        #else
        fallbackLiquidGlass(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    @ViewBuilder
    private func nativeLiquidGlass(_ content: Content) -> some View {
        let glass: Glass = {
            var base = Glass.regular
            if let tint {
                base = base.tint(tint)
            }
            if interactive {
                base = base.interactive()
            }
            return base
        }()

        content
            .glassEffect(glass, in: shape)
    }
    #endif

    @ViewBuilder
    private func fallbackLiquidGlass(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)

                    if let tint {
                        shape.fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    }

                    // Soft internal sheen mimicking liquid refraction
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.45),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.28 : 0.85),
                            Color.white.opacity(colorScheme == .dark ? 0.06 : 0.20),
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.07),
                radius: shadowRadius,
                x: 0,
                y: shadowRadius * 0.45
            )
    }
}

extension View {
    /// Applies Apple's native iOS 26 Liquid Glass (with rich specular fallback on iOS 17–18).
    func aionLiquidGlass<S: InsettableShape>(
        in shape: S = Capsule(),
        tint: Color? = nil,
        interactive: Bool = true,
        shadowRadius: CGFloat = 14
    ) -> some View {
        modifier(
            AionLiquidGlassModifier(
                shape: shape,
                tint: tint,
                interactive: interactive,
                shadowRadius: shadowRadius
            )
        )
    }

    /// Subtle Bento card surface with warm adaptive elevation & optional Liquid Glass sheen.
    func aionBentoCard(
        fill: Color = AionTheme.surface,
        cornerRadius: CGFloat = AionTheme.cardRadius
    ) -> some View {
        modifier(AionBentoCardModifier(fill: fill, cornerRadius: cornerRadius))
    }
}

private struct AionBentoCardModifier: ViewModifier {
    let fill: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(fill)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.42),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.72),
                            AionTheme.border
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.045),
                radius: 12,
                x: 0,
                y: 5
            )
    }
}

/// Tactile bouncy spring press style for Bento cards & glass controls.
struct AionSpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.965

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Soft ambient backdrop so Liquid Glass elements refract subtle warm light in both Light & Dark mode.
struct AionAmbientCanvas: View {
    var body: some View {
        ZStack {
            AionTheme.canvas

            RadialGradient(
                colors: [AionTheme.ambientGlowTop, .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 340
            )

            RadialGradient(
                colors: [AionTheme.ambientGlowMid, .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}
