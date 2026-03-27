import SwiftUI

@Observable @MainActor
class PaletteStore {
    struct GameColor: Identifiable {
        let id: String
        let label: String
        let defaultHex: String
        var defaultColor: Color { Color(hex: defaultHex) }
    }

    static let definitions: [GameColor] = [
        GameColor(id: "olive", label: "Olive", defaultHex: "#66801E"),
        GameColor(id: "orangeRed", label: "Red", defaultHex: "#ED3F1C"),
        GameColor(id: "orange", label: "Orange", defaultHex: "#ED8008"),
        GameColor(id: "blueGray", label: "Blue", defaultHex: "#395C7D"),
        GameColor(id: "silver", label: "Silver", defaultHex: "#AAB7BF"),
        GameColor(id: "taupe", label: "Taupe", defaultHex: "#736356"),
    ]

    enum AppearanceMode: String, CaseIterable {
        case light, dark
        var label: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        var colorScheme: ColorScheme {
            self == .dark ? .dark : .light
        }
    }

    var colors: [String: Color] = [:]
    var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var olive: Color { colors["olive"]! }
    var orangeRed: Color { colors["orangeRed"]! }
    var orange: Color { colors["orange"]! }
    var blueGray: Color { colors["blueGray"]! }
    var silver: Color { colors["silver"]! }
    var taupe: Color { colors["taupe"]! }

    init() {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? "light"
        self.appearanceMode = AppearanceMode(rawValue: raw) ?? .light
        for def in Self.definitions {
            if let hex = UserDefaults.standard.string(forKey: "palette_\(def.id)") {
                colors[def.id] = Color(hex: hex)
            } else {
                colors[def.id] = def.defaultColor
            }
        }
    }

    func color(for type: TileType) -> Color {
        switch type {
        case .olive: olive
        case .red: orangeRed
        case .orange: orange
        case .blue: blueGray
        case .silver: silver
        case .taupe: taupe
        }
    }

    func save() {
        for (key, color) in colors {
            UserDefaults.standard.set(color.hexString, forKey: "palette_\(key)")
        }
    }

    func reset() {
        for def in Self.definitions {
            colors[def.id] = def.defaultColor
            UserDefaults.standard.removeObject(forKey: "palette_\(def.id)")
        }
    }

    var isCustomized: Bool {
        Self.definitions.contains { def in
            UserDefaults.standard.string(forKey: "palette_\(def.id)") != nil
        }
    }
}

extension Color {
    var hexString: String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
