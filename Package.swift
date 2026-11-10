// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniversalControlHelper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "UniversalControlHelper", targets: ["UniversalControlHelper"])],
    dependencies: [],
    targets: [.executableTarget(name: "UniversalControlHelper")]
)
