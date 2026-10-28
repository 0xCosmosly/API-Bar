// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "APIBar", platforms: [.macOS(.v13)], products: [.executable(name: "APIBar", targets: ["APIBar"])], targets: [.executableTarget(name: "APIBar", path: "Sources")])
