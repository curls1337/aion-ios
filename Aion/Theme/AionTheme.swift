import SwiftUI
import UIKit

/// Warm Modern Bento Design Tokens (Concept 3) with full Adaptive Light & Dark Mode
enum AionTheme {
    // MARK: - Core Canvas & Surfaces

    /// Warm Ivory (#FAF8F5) in Light, Deep Warm Obsidian (#121110) in Dark
    static let canvas = Color.adaptive(light: 0xFAF8F5, dark: 0x121110)

    /// Elevated card surface (#FFFFFF in Light, #1C1A18 in Dark)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1A18)

    /// Secondary grouped surface (#F3EFE9 in Light, #24211E in Dark)
    static let surfaceSecondary = Color.adaptive(light: 0xF3EFE9, dark: 0x24211E)

    /// Subtle hairline border
    static let border = Color.adaptive(
        light: UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 0.07),
        dark: UIColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 0.10)
    )

    // MARK: - Typography Ink

    /// Primary ink (#1C1B19 in Light, #F4EFEA in Dark)
    static let inkPrimary = Color.adaptive(light: 0x1C1B19, dark: 0xF4EFEA)

    /// Secondary warm stone ink (#6E6A63 in Light, #A39D94 in Dark)
    static let inkSecondary = Color.adaptive(light: 0x6E6A63, dark: 0xA39D94)

    /// Tertiary muted ink
    static let inkTertiary = Color.adaptive(light: 0x9C968E, dark: 0x736E67)

    // MARK: - Brand & Semantic Accents

    /// Warm Terracotta Coral (#D97757 Light / #E88B6B Dark)
    static let terracotta = Color.adaptive(light: 0xD97757, dark: 0xE88B6B)

    /// Deep Forest Sage (#2F6F5E Light / #5BB99B Dark)
    static let forest = Color.adaptive(light: 0x2F6F5E, dark: 0x5BB99B)

    /// Soft Editorial Indigo (#6B5CA5 Light / #A594F9 Dark)
    static let lavenderAccent = Color.adaptive(light: 0x6B5CA5, dark: 0xA594F9)

    /// Amber Warning / Pending
    static let amber = Color.adaptive(light: 0xC88A2B, dark: 0xE5A94C)

    // MARK: - Bento Card Tints (Adaptive Pastel Light / Deep Translucent Dark)

    static let bentoSand = Color.adaptive(light: 0xEFE0CE, dark: 0x2E211A)
    static let bentoSage = Color.adaptive(light: 0xD7E4DC, dark: 0x1A2923)
    static let bentoLavender = Color.adaptive(light: 0xDFDCF0, dark: 0x231F31)
    static let bentoAlabaster = Color.adaptive(light: 0xFFFFFF, dark: 0x211F1C)

    // MARK: - Code Block & Attachments

    static let codeBackground = Color.adaptive(light: 0xF4F1EC, dark: 0x161514)
    static let fileChipBackground = Color.adaptive(light: 0xF5EFE8, dark: 0x2A2521)

    // MARK: - Ambient Mesh / Background Glow

    static let ambientGlowTop = Color.adaptive(
        light: UIColor(red: 0.93, green: 0.85, blue: 0.76, alpha: 0.32),
        dark: UIColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 0.14)
    )

    static let ambientGlowMid = Color.adaptive(
        light: UIColor(red: 0.83, green: 0.89, blue: 0.85, alpha: 0.28),
        dark: UIColor(red: 0.25, green: 0.49, blue: 0.42, alpha: 0.12)
    )

    // MARK: - Layout Metrics

    static let cardRadius: CGFloat = 24
    static let innerRadius: CGFloat = 16
    static let pillRadius: CGFloat = 999
}

// MARK: - Color Hex & Adaptive Helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        })
    }

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Appearance Preference

enum AionAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "System"
    case light = "Warm Light"
    case dark = "Obsidian Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}
