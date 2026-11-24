import AppKit
import BatizadoCore

extension MenuBarIcon {
    /// Template images, so the menu bar tints them; the four states differ in shape, never in color.
    @MainActor var image: NSImage { Self.images[self]! }

    var accessibilityLabel: String {
        switch self {
        case .off: "Batizado: off"
        case .awake: "Batizado: Keep awake on"
        case .closedLid: "Batizado: Closed lid on"
        case .diverged: "Batizado: Closed lid does not match the system"
        }
    }

    @MainActor private static let images: [MenuBarIcon: NSImage] = [
        .off: draw(.off, base: "cup.and.saucer"),
        .awake: draw(.awake, base: "cup.and.heat.waves"),
        .closedLid: draw(.closedLid, base: "cup.and.heat.waves.fill"),
        .diverged: draw(.diverged, base: "cup.and.saucer", badge: "exclamationmark.triangle.fill"),
    ]

    private static func draw(_ icon: MenuBarIcon, base: String, badge: String? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { bounds in
            guard let cup = symbol(base, size: 15, weight: .medium) else { return false }
            let shift: CGFloat = badge == nil ? 0 : 2
            cup.draw(in: centered(cup.size, in: bounds, offsetX: -shift))
            guard let badge, let mark = symbol(badge, size: 9, weight: .bold) else { return true }
            let center = NSPoint(x: bounds.maxX - 5, y: 5)
            // Punch a gap around the badge so it stays a separate shape on top of the cup.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            mark.draw(
                in: NSRect(
                    x: center.x - mark.size.width / 2, y: center.y - mark.size.height / 2,
                    width: mark.size.width, height: mark.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = icon.accessibilityLabel
        return image
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    private static func centered(_ size: NSSize, in bounds: NSRect, offsetX: CGFloat) -> NSRect {
        NSRect(
            x: (bounds.width - size.width) / 2 + offsetX, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height)
    }
}
