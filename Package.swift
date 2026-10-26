// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Takes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Takes",
            path: "Sources/Takes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
