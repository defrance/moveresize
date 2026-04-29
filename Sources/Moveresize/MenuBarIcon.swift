import AppKit

enum MenuBarIcon {
    static func load() -> NSImage {
        if let image = bundledImage() {
            image.isTemplate = true
            return image
        }

        return make()
    }

    /// Draws an 18×18 template image: anchor at bottom-left, arrowhead at top-right.
    /// The shaft exits from the anchor's ring toward the northeast arrowhead.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(1.3)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            drawArrowhead(ctx)
            drawShaft(ctx)
            drawAnchor(ctx)

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Private drawing

    private static func bundledImage() -> NSImage? {
        let supportedExtensions = ["png", "jpg", "jpeg", "icns", "ico"]

        for fileExtension in supportedExtensions {
            if let url = AppResources.bundle.url(forResource: "MenuBarIcon", withExtension: fileExtension),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    /// Filled right-angle triangle pointing northeast. Tip at (16, 16.5).
    private static func drawArrowhead(_ ctx: CGContext) {
        ctx.move(to: CGPoint(x: 16, y: 16.5))
        ctx.addLine(to: CGPoint(x: 16, y: 10.5))
        ctx.addLine(to: CGPoint(x: 10, y: 16.5))
        ctx.closePath()
        ctx.fillPath()
    }

    /// Diagonal shaft from the anchor crown to the arrowhead.
    private static func drawShaft(_ ctx: CGContext) {
        ctx.move(to: CGPoint(x: 5.7, y: 8.1))
        ctx.addLine(to: CGPoint(x: 12, y: 13.5))
        ctx.strokePath()
    }

    /// Stylized anchor: lower semi-arc with pointed ends and a short crown.
    private static func drawAnchor(_ ctx: CGContext) {
        let center = CGPoint(x: 4.3, y: 5.0)
        let radius: CGFloat = 2.6
        let leftAngle = CGFloat.pi * 1.15
        let rightAngle = CGFloat.pi * 1.85

        let leftEnd = CGPoint(
            x: center.x + cos(leftAngle) * radius,
            y: center.y + sin(leftAngle) * radius
        )
        let rightEnd = CGPoint(
            x: center.x + cos(rightAngle) * radius,
            y: center.y + sin(rightAngle) * radius
        )

        // Curved base of the anchor.
        ctx.addArc(center: center, radius: radius, startAngle: leftAngle, endAngle: rightAngle, clockwise: false)
        ctx.strokePath()

        // Left pointed tip.
        ctx.move(to: leftEnd)
        ctx.addLine(to: CGPoint(x: leftEnd.x - 1.1, y: leftEnd.y + 1.2))
        ctx.addLine(to: CGPoint(x: leftEnd.x + 0.5, y: leftEnd.y + 0.8))
        ctx.closePath()
        ctx.fillPath()

        // Right pointed tip.
        ctx.move(to: rightEnd)
        ctx.addLine(to: CGPoint(x: rightEnd.x + 1.1, y: rightEnd.y + 1.2))
        ctx.addLine(to: CGPoint(x: rightEnd.x - 0.5, y: rightEnd.y + 0.8))
        ctx.closePath()
        ctx.fillPath()

        // Small crown that connects visually to the diagonal shaft.
        ctx.move(to: CGPoint(x: center.x + 0.1, y: center.y + radius - 0.1))
        ctx.addLine(to: CGPoint(x: 5.7, y: 8.1))
        ctx.strokePath()
    }
}
