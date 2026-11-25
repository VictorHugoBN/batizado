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

    @MainActor private static let images: [MenuBarIcon: NSImage] = Dictionary(
        uniqueKeysWithValues: [MenuBarIcon.off, .awake, .closedLid, .diverged].map { ($0, render($0)) })

    private static func render(_ icon: MenuBarIcon) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            CupGlyph.draw(icon, in: context, bounds: bounds)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = icon.accessibilityLabel
        return image
    }
}

/// The cup drawings, in the units of a 25 x 21 grid whose origin is at (-0.5, -0.5), y pointing down.
private enum CupGlyph {
    static let stroke: CGFloat = 1.5
    /// Slightly under 18/21 so the cup walls and the saucer land on whole pixels on a non-Retina display.
    static let scale: CGFloat = 0.82

    static func draw(_ icon: MenuBarIcon, in context: CGContext, bounds: CGRect) {
        // Left wall centered on x = 6.5 pt, saucer centered on y = 16.5 pt.
        context.translateBy(x: 6.5 - 6.5 * scale, y: 16.5 - 19.9 * scale)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0.5, y: 0.5)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)

        switch icon {
        case .off:
            cup(context, filled: false)
        case .awake:
            cup(context, filled: false)
            for x in [9.5, 13.5] {
                context.addPath(steam(x: x))
                context.strokePath()
            }
        case .closedLid:
            cup(context, filled: true)
            context.setLineWidth(0.5)
            context.addPath(bottle())
            context.drawPath(using: .eoFillStroke)
            context.setLineWidth(stroke)
            context.addPath(stream())
            context.strokePath()
        case .diverged:
            context.saveGState()
            context.translateBy(x: -2.5, y: 0)
            cup(context, filled: false)
            context.restoreGState()
            badge(context)
        }
    }

    /// The cup and its saucer sit in the same place in every state, so only the extras change.
    private static func cup(_ context: CGContext, filled: Bool) {
        context.saveGState()
        context.translateBy(x: 0, y: 0.6)
        context.addPath(body())
        context.drawPath(using: filled ? .fillStroke : .stroke)
        context.addPath(handle())
        context.addPath(line(from: CGPoint(x: 5.5, y: 18.8), to: CGPoint(x: 17.5, y: 18.8)))
        context.strokePath()
        context.restoreGState()
    }

    private static func body() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 8.5))
        path.addLine(to: CGPoint(x: 17, y: 8.5))
        path.addArc(tangent1End: CGPoint(x: 17, y: 16.5), tangent2End: CGPoint(x: 12.5, y: 16.5), radius: 4.5)
        path.addArc(tangent1End: CGPoint(x: 6, y: 16.5), tangent2End: CGPoint(x: 6, y: 12), radius: 4.5)
        path.closeSubpath()
        return path
    }

    private static func handle() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 17, y: 9.8))
        path.addArc(tangent1End: CGPoint(x: 20, y: 9.8), tangent2End: CGPoint(x: 20, y: 12), radius: 2.2)
        path.addArc(tangent1End: CGPoint(x: 20, y: 14.2), tangent2End: CGPoint(x: 17.8, y: 14.2), radius: 2.2)
        path.addLine(to: CGPoint(x: 16.5, y: 14.2))
        return path
    }

    private static func steam(x: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: 6.9))
        path.addCurve(
            to: CGPoint(x: x, y: 3.6), control1: CGPoint(x: x - 0.9, y: 5.8),
            control2: CGPoint(x: x + 0.9, y: 4.8))
        return path
    }

    /// A bottle tipped toward the cup from the top left, with its label cut out.
    private static func bottle() -> CGPath {
        let path = CGMutablePath()
        let tilt = CGAffineTransform(translationX: 10.1, y: 4.6).rotated(by: 105 * .pi / 180)
        let outline: [CGPoint] = [
            CGPoint(x: -0.9, y: 0), CGPoint(x: 0.9, y: 0), CGPoint(x: 0.9, y: 2.6), CGPoint(x: 2.4, y: 4),
        ]
        path.addLines(between: outline, transform: tilt)
        path.addArc(
            tangent1End: CGPoint(x: 2.4, y: 9.5), tangent2End: CGPoint(x: 1.6, y: 9.5), radius: 0.8,
            transform: tilt)
        path.addArc(
            tangent1End: CGPoint(x: -2.4, y: 9.5), tangent2End: CGPoint(x: -2.4, y: 8.7), radius: 0.8,
            transform: tilt)
        path.addLine(to: CGPoint(x: -2.4, y: 4), transform: tilt)
        path.addLine(to: CGPoint(x: -0.9, y: 2.6), transform: tilt)
        path.closeSubpath()
        path.addRect(CGRect(x: -1.5, y: 5.3, width: 3, height: 2.3), transform: tilt)
        return path
    }

    private static func stream() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10.1, y: 5.7))
        path.addQuadCurve(to: CGPoint(x: 11.4, y: 8.4), control: CGPoint(x: 11.3, y: 6.4))
        return path
    }

    /// A warning triangle with the exclamation mark cut out, set off from the cup by a clear ring.
    private static func badge(_ context: CGContext) {
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 19.4 - 5.9, y: 14.6 - 5.9, width: 11.8, height: 11.8))
        context.setBlendMode(.normal)

        let triangle = CGMutablePath()
        triangle.addLines(between: [
            CGPoint(x: 19.4, y: 11), CGPoint(x: 23.3, y: 18), CGPoint(x: 15.5, y: 18),
        ])
        triangle.closeSubpath()
        context.setLineWidth(1.4)
        context.addPath(triangle)
        context.drawPath(using: .fillStroke)

        context.setBlendMode(.clear)
        for mark in [
            CGRect(x: 18.9, y: 13.2, width: 1, height: 2.6), CGRect(x: 18.9, y: 16.5, width: 1, height: 1),
        ] {
            context.addPath(CGPath(roundedRect: mark, cornerWidth: 0.3, cornerHeight: 0.3, transform: nil))
            context.fillPath()
        }
        context.setBlendMode(.normal)
    }

    private static func line(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [start, end])
        return path
    }
}
