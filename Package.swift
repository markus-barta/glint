// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Nuncid",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Nuncid", targets: ["Nuncid"])],
    targets: [
        .executableTarget(
            name: "Nuncid",
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
