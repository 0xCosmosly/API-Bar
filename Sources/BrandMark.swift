import AppKit

/// Original API Bar artwork: opposed inputs and two open enclosing arcs.
/// Uses the inward-connection concept studied in Kuwayama, not a traced mark.
@MainActor enum BrandMark {
    static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 18, y: rect.height / 18)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.butt)
        context.addArc(center: CGPoint(x: 9, y: 9), radius: 7.1, startAngle: 93 * .pi / 180, endAngle: 173 * .pi / 180, clockwise: false)
        context.strokePath()
        context.addArc(center: CGPoint(x: 9, y: 9), radius: 7.1, startAngle: -87 * .pi / 180, endAngle: -7 * .pi / 180, clockwise: false)
        context.strokePath()
        context.setLineWidth(1.8)
        context.setLineCap(.butt)
        context.move(to: CGPoint(x: 1.2, y: 9))
        context.addLine(to: CGPoint(x: 16.8, y: 9))
        context.strokePath()
        context.restoreGState()
    }

    static func appIconImage(size: CGFloat = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let inset = size * 0.094
        let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2), xRadius: size * 0.18, yRadius: size * 0.18)
        NSColor.white.setFill(); tile.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke(); tile.lineWidth = max(1, size * 0.005); tile.stroke()
        let markInset = size * 0.254
        draw(in: NSRect(x: markInset, y: markInset, width: size - markInset * 2, height: size - markInset * 2))
        image.unlockFocus()
        return image
    }

    private static var cached: NSImage?
    static func image() -> NSImage {
        if let cached { return cached }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for scale in [1, 2, 3] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.current = context
            draw(in: NSRect(origin: .zero, size: size))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = true; cached = image
        return image
    }
}
