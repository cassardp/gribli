import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64

        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = (
                ((int >> 8) & 0xF) * 17,
                ((int >> 4) & 0xF) * 17,
                (int & 0xF) * 17,
                255
            )

        case 6: // RRGGBB (24-bit)
            (r, g, b, a) = (
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF,
                255
            )

        case 8: // RRGGBBAA (32-bit)
            (r, g, b, a) = (
                (int >> 24) & 0xFF,
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF
            )

        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Palette

enum Palette {
    // MARK: - Tile colors (Dieter Rams / Braun)

    static let olive     = Color(hex: "#66801E")
    static let orangeRed = Color(hex: "#ED3F1C")
    static let orange    = Color(hex: "#ED8008")
    static let blueGray  = Color(hex: "#395C7D")
    static let silver    = Color(hex: "#AAB7BF")
    static let taupe     = Color(hex: "#736356")

    // MARK: - UI colors

    static let cream     = Color(hex: "#E8E2D9")
    static let espresso  = Color(hex: "#261201")
    static let warmBlack = Color(hex: "#1C1712")
    static let sand      = Color(hex: "#D9D2C6")

    // MARK: - Semantic helpers

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? warmBlack : cream
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? sand : espresso
    }
}
