import SwiftUI

/// Coffee tones for the popover. Every text color keeps at least 4.5:1 against the light and dark panel.
enum Palette {
    static let accent = Tone(light: 0x7A4A2E, dark: 0xD29A66)
    static let icon = Tone(light: 0x8A5A3C, dark: 0xD7A982)
    static let track = Tone(light: 0xE6DBD0, dark: 0x4A3F38)
    /// Outline of a switch that is off, at 3:1 so the control is visible without its fill.
    static let trackEdge = Tone(light: 0x957F6F, dark: 0x93806F)
    static let warning = Tone(light: 0xA3400F, dark: 0xF59A5B)
    static let highlight = Tone(light: 0x7A4A2E, dark: 0xD29A66, opacity: 0.12)
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
