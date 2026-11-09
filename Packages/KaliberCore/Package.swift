// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KaliberCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KaliberCore", targets: ["KaliberCore"]),
    ],
    targets: [
        .target(
            name: "KaliberCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "KaliberCoreTests",
            dependencies: ["KaliberCore"]
        ),
    ]
)
