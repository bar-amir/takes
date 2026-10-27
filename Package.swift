// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Takes",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-updates. Pinned exactly; bump deliberately (Dependabot opens PRs).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Takes",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Takes",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is embedded in Takes.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "TakesTests",
            dependencies: ["Takes"],
            path: "Tests/TakesTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
