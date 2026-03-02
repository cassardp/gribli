import SwiftUI

enum Palette {
    // MARK: - Tile colors (Dieter Rams / Braun)

    static let olive = Color(red: 0.40, green: 0.50, blue: 0.12)         // #668014
    static let orangeRed = Color(red: 0.929, green: 0.247, blue: 0.110)  // #ED3F1C
    static let orange = Color(red: 0.929, green: 0.502, blue: 0.031)     // #ED8008
    static let blueGray = Color(red: 0.231, green: 0.294, blue: 0.349)   // #3B4B59
    static let silver = Color(red: 0.667, green: 0.718, blue: 0.749)     // #AAB7BF
    static let taupe = Color(red: 0.451, green: 0.388, blue: 0.337)      // #736356

    // MARK: - UI colors

    static let cream = Color(red: 0.91, green: 0.886, blue: 0.851)       // #E8E2D9
    static let espresso = Color(red: 0.149, green: 0.071, blue: 0.004)   // #261201
    static let warmBlack = Color(red: 0.11, green: 0.09, blue: 0.07)     // #1C1712
    static let sand = Color(red: 0.851, green: 0.824, blue: 0.776)       // #D9D2C6

    // MARK: - Semantic helpers

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? warmBlack : cream
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? sand : espresso
    }
}
