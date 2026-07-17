// swift-tools-version:6.0
import PackageDescription

// NOTE: XCTest / swift-testing are unavailable with Command Line Tools only
// (they ship with full Xcode). To keep tests runnable without Xcode, the test
// suite is a plain executable target with a tiny assertion harness. Run it with
// `swift run UsageKitTests`.
let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageKit"),
        .executableTarget(
            name: "Headroom",
            dependencies: ["UsageKit"]
        ),
        .executableTarget(
            name: "UsageKitTests",
            dependencies: ["UsageKit"],
            path: "Tests/UsageKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
