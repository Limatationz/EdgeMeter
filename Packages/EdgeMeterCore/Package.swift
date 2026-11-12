// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeMeterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EdgeMeterCore", targets: ["EdgeMeterCore"]),
    ],
    targets: [
        .target(
            name: "EdgeMeterCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "EdgeMeterCoreTests",
            dependencies: ["EdgeMeterCore"]
        ),
    ]
)
