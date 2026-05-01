import AppKit

enum MenuBarIcon {
    static func load() -> NSImage {
        return make()
    }

    /// Draws an 18x18 template image: resize arrow inside a keyboard-like keycap.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(1.3)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            drawKeycap(ctx)
            drawArrow(ctx)

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Rounded rectangle evoking a keyboard key.
    private static func drawKeycap(_ ctx: CGContext) {
        let keycap = CGRect(x: 1.3, y: 1.3, width: 15.4, height: 15.4)
        let path = CGPath(roundedRect: keycap, cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)

        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Diagonal resize arrow (northeast) inside the keycap.
    private static func drawArrow(_ ctx: CGContext) {
        ctx.move(to: CGPoint(x: 5.2, y: 5.2))
        ctx.addLine(to: CGPoint(x: 12.1, y: 12.1))

        ctx.move(to: CGPoint(x: 12.1, y: 12.1))
        ctx.addLine(to: CGPoint(x: 12.1, y: 8.5))

        ctx.move(to: CGPoint(x: 12.1, y: 12.1))
        ctx.addLine(to: CGPoint(x: 8.5, y: 12.1))

        ctx.strokePath()
    }
}
