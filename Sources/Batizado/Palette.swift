import SwiftUI

/// Rum amber for what is on, coffee for the rest. Every text color keeps at least 4.5:1 against the light
/// (#E4E4E4 to white) and dark (#1E1E1E to #3A3A3A) panel.
enum Palette {
    static let accent = Tone(light: 0x8A5600, dark: 0xE3962F)
    static let icon = Tone(light: 0x8A5A3C, dark: 0xD7A982)
    static let track = Tone(light: 0xE6DBD0, dark: 0x4A3F38)
    /// Outline of a switch that is off, at 3:1 so the control is visible without its fill.
    static let trackEdge = Tone(light: 0x927C6C, dark: 0x93806F)
    /// Red rather than orange, so a warning never reads as the amber accent.
    static let warning = Tone(light: 0xB42318, dark: 0xFF8C7A)
    static let highlight = Tone(light: 0x8A5600, dark: 0xE3962F, opacity: 0.12)
}

struct Tone: ShapeStyle {
    let light: Color
    let dark: Color

    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.light = Color(hex: light).opacity(opacity)
        self.dark = Color(hex: dark).opacity(opacity)
    }

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
