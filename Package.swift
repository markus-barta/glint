// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Glint", targets: ["Glint"])],
    targets: [.executableTarget(name: "Glint")],
    swiftLanguageVersions: [.v5]
)
