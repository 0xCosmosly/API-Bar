import AppKit

// AppKit vector artwork, rendered at every native macOS icon size.
@main enum MakeIcon {
@MainActor static func main() throws {
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func artwork() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 188, yRadius: 188)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor.white.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setFill(); tile.fill()
    NSColor.black.withAlphaComponent(0.08).setStroke(); tile.lineWidth = 3; tile.stroke()
    BrandMark.draw(in: NSRect(x: 260, y: 260, width: 504, height: 504))

}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        artwork()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

// Assemble the PNG-backed ICNS directly, including standard and Retina entries.
// This keeps icon generation independent of iconutil's system service access.
if CommandLine.arguments.count > 2 {
    func length(_ value: Int) -> Data {
        var bytes = UInt32(value).bigEndian
        return withUnsafeBytes(of: &bytes) { Data($0) }
    }
    let entries = [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png")
    ]
    var body = Data()
    for (tag, filename) in entries {
        let png = try Data(contentsOf: destination.appendingPathComponent(filename))
        body.append(Data(tag.utf8)); body.append(length(png.count + 8)); body.append(png)
    }
    var icon = Data("icns".utf8)
    icon.append(length(body.count + 8)); icon.append(body)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}

}
}
