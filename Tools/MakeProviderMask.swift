import AppKit

// Generates the alpha-template brand masks in Resources/ from each provider's own
// vector mark, so the menu bar and badge tiles can tint them with the brand accent
// exactly like the hand-made masks for the older providers.
//
// usage: MakeProviderMask <provider> <output.png>
@main enum MakeProviderMask {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count > 2 else {
            FileHandle.standardError.write(Data("usage: MakeProviderMask <provider> <output.png>\n".utf8))
            exit(2)
        }
        let provider = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        // 3x of a 32pt design grid keeps edges crisp on Retina menu bars.
        guard let cgImage = ProviderMarkGeometry.image(for: provider, pixels: 96) else {
            FileHandle.standardError.write(Data("unknown provider: \(provider)\n".utf8))
            exit(2)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MakeProviderMask", code: 2)
        }
        try png.write(to: output, options: .atomic)
        print("Wrote \(output.path)")
    }
}
