import AppKit

// Generates the alpha-template brand masks in Resources/ from each provider's own
// vector mark, so the menu bar and badge tiles can tint them with the brand accent
// exactly like the hand-made masks for the older providers.
//
// usage: MakeProviderMask <provider> <output.png>
@main enum MakeProviderMask {
    /// Straight-line polygons in the provider's own coordinate space.
    struct Mark {
        let canvas: CGFloat
        let polygons: [[CGPoint]]
        let filledSquares: [CGRect] = []
    }

    static func mark(for provider: String) -> Mark? {
        switch provider {
        case "unaligned":
            // unaligned.pw site icon: a 32-unit grid, two overlapping squares
            // (back 5,5 15x15 and front 13,13 14x14).
            return Mark(canvas: 32, polygons: [
                [CGPoint(x: 5, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 20, y: 20), CGPoint(x: 5, y: 20)],
                [CGPoint(x: 13, y: 13), CGPoint(x: 27, y: 13), CGPoint(x: 27, y: 27), CGPoint(x: 13, y: 27)]
            ])
        case "yeta":
            // platform.yeta.ai /yeta-mark.svg: two chevrons plus two inner strokes,
            // traced from the published 364-unit viewBox.
            return Mark(canvas: 364, polygons: [
                [CGPoint(x: 32, y: 37), CGPoint(x: 169, y: 127), CGPoint(x: 169, y: 324), CGPoint(x: 132, y: 301), CGPoint(x: 132, y: 148), CGPoint(x: 32, y: 89)],
                [CGPoint(x: 332, y: 37), CGPoint(x: 195, y: 127), CGPoint(x: 195, y: 324), CGPoint(x: 232, y: 301), CGPoint(x: 232, y: 148), CGPoint(x: 332, y: 89)],
                [CGPoint(x: 32, y: 131), CGPoint(x: 99, y: 174), CGPoint(x: 99, y: 216), CGPoint(x: 32, y: 174)],
                [CGPoint(x: 332, y: 131), CGPoint(x: 265, y: 174), CGPoint(x: 265, y: 216), CGPoint(x: 332, y: 174)]
            ])
        default:
            return nil
        }
    }

    @MainActor static func main() throws {
        guard CommandLine.arguments.count > 2 else {
            FileHandle.standardError.write(Data("usage: MakeProviderMask <provider> <output.png>\n".utf8))
            exit(2)
        }
        let provider = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let mark = mark(for: provider) else {
            FileHandle.standardError.write(Data("unknown provider: \(provider)\n".utf8))
            exit(2)
        }

        // 3x of a 32pt design grid keeps edges crisp on Retina menu bars.
        let pixels = 96
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "MakeProviderMask", code: 1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        // Source marks use top-down coordinates; AppKit fills bottom-up.
        context.cgContext.translateBy(x: 0, y: CGFloat(pixels))
        context.cgContext.scaleBy(x: 1, y: -1)

        let scale = CGFloat(pixels) / mark.canvas
        NSColor.white.setFill()
        for polygon in mark.polygons where polygon.count >= 3 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: polygon[0].x * scale, y: polygon[0].y * scale))
            for point in polygon.dropFirst() {
                path.line(to: NSPoint(x: point.x * scale, y: point.y * scale))
            }
            path.close()
            path.fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MakeProviderMask", code: 2)
        }
        try png.write(to: output, options: .atomic)
        print("Wrote \(output.path)")
    }
}
