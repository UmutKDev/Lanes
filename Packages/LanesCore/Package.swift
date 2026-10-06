// swift-tools-version: 6.0
import PackageDescription

// LanesCore holds the logic that does not need AppKit: profiles, launch plans,
// process argument parsing, claude:// link rules and the Faz 0 report model.
// It builds on Linux too, so its tests run in any CI runner.
let package = Package(
    name: "LanesCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LanesCore", targets: ["LanesCore"]),
    ],
    targets: [
        .target(name: "LanesCore"),
        .testTarget(name: "LanesCoreTests", dependencies: ["LanesCore"]),
    ]
)
