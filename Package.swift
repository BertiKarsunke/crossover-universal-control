// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Crossover",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Crossover", targets: ["Crossover"])],
    dependencies: [],
    targets: [.executableTarget(name: "Crossover", resources: [.copy("Resources")])]
)
