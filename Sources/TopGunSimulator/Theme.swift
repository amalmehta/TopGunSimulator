import SwiftUI
import AppKit
import FlightCore

extension Color {
    /// A colour with separate light- and dark-mode values.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Lesson categories are colour-coded by family: Airwork = blues, Takeoff & Landing = greens,
/// Top Gun = reds/oranges. Shades within a family are far enough apart to tell at a glance.
extension LessonCategory {
    var color: Color {
        switch self {
        case .basics:    return Color(light: NSColor(hex: 0x3D9BF0), dark: NSColor(hex: 0x74BAFF))
        case .maneuvers: return Color(light: NSColor(hex: 0x2443B8), dark: NSColor(hex: 0x6C7DFF))
        case .takeoff:   return Color(light: NSColor(hex: 0x2FB36B), dark: NSColor(hex: 0x5BE39A))
        case .landing:   return Color(light: NSColor(hex: 0x146B3E), dark: NSColor(hex: 0x2E9E62))
        case .canyon:    return Color(light: NSColor(hex: 0xEA7A12), dark: NSColor(hex: 0xFFA552))
        case .dogfight:  return Color(light: NSColor(hex: 0xC4232B), dark: NSColor(hex: 0xFF5C61))
        }
    }

    var symbol: String {
        switch self {
        case .basics: return "gamecontroller"
        case .maneuvers: return "arrow.triangle.turn.up.right.diamond"
        case .takeoff: return "airplane.departure"
        case .landing: return "airplane.arrival"
        case .canyon: return "mountain.2"
        case .dogfight: return "scope"
        }
    }
}

extension Hint.Severity {
    var color: Color {
        switch self {
        case .info:    return Color(light: NSColor(hex: 0x1F7A8C), dark: NSColor(hex: 0x5CC8DB))
        case .caution: return Color(light: NSColor(hex: 0xB7791F), dark: NSColor(hex: 0xF6C350))
        case .warning: return Color(light: NSColor(hex: 0xC53030), dark: NSColor(hex: 0xFF6B6B))
        }
    }
    var symbol: String {
        switch self {
        case .info: return "lightbulb"
        case .caution: return "exclamationmark.triangle"
        case .warning: return "exclamationmark.octagon.fill"
        }
    }
}

enum HUDColor {
    static let symbology = Color(red: 0.35, green: 1.0, blue: 0.45)
    static let warning = Color(red: 1.0, green: 0.3, blue: 0.25)
    static let bandit = Color(red: 1.0, green: 0.25, blue: 0.25)
    static let gate = Color(red: 1.0, green: 0.62, blue: 0.1)
}
