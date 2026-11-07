import CoreGraphics
import Foundation

/// Vector geometry for provider marks whose brand artwork is a simple polygon set.
///
/// Shared by the mask build tool and the app itself: if a `-mask.png` is missing
/// from the bundle (an older build, or a provider list that arrived over iCloud
/// before the matching binary), the app draws the mark from this geometry instead
/// of silently falling back to a letter monogram.
///
/// Coordinates are the provider's own space, with the origin at the top-left, which
/// matches how the source artwork is published.
enum ProviderMarkGeometry {
    struct Mark {
        let canvas: CGFloat
        let polygons: [[CGPoint]]
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
        case "heimdallm":
            // staging.heimdallm.com icon.svg: Norse "H" gate glyph (32-unit viewBox)
            // Top bar, two uprights, and diagonal crossbar.
            return Mark(canvas: 32, polygons: [
                [CGPoint(x: 4, y: 4), CGPoint(x: 28, y: 4), CGPoint(x: 28, y: 8), CGPoint(x: 4, y: 8)],
                [CGPoint(x: 6, y: 10), CGPoint(x: 11, y: 10), CGPoint(x: 11, y: 28), CGPoint(x: 6, y: 28)],
                [CGPoint(x: 21, y: 10), CGPoint(x: 26, y: 10), CGPoint(x: 26, y: 28), CGPoint(x: 21, y: 28)],
                [CGPoint(x: 6.1, y: 19.55), CGPoint(x: 24.69, y: 14.22), CGPoint(x: 25.9, y: 18.45), CGPoint(x: 7.31, y: 23.78)]
            ])
        default:
            return nil
        }
    }

    /// Renders a mark into an alpha-only CGImage of `pixels` square.
    static func image(for provider: String, pixels: Int) -> CGImage? {
        guard let mark = mark(for: provider),
              let context = CGContext(data: nil,
                                      width: pixels,
                                      height: pixels,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        // Source marks are top-down; CoreGraphics draws bottom-up.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)
        let scale = CGFloat(pixels) / mark.canvas
        context.setFillColor(NSColorBlack)
        for polygon in mark.polygons where polygon.count >= 3 {
            context.beginPath()
            context.move(to: CGPoint(x: polygon[0].x * scale, y: polygon[0].y * scale))
            for point in polygon.dropFirst() {
                context.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
            }
            context.closePath()
            context.fillPath()
        }
        return context.makeImage()
    }

    private static let NSColorBlack = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
}
