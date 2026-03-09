// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CortexVision",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CortexVision", targets: ["CortexVision"]),
    ],
    targets: [
        .target(
            name: "CortexVision",
            path: "Sources/CortexVision"
        ),
        .testTarget(
            name: "CortexVisionTests",
            dependencies: ["CortexVision"],
            path: "Tests/CortexVisionTests",
            resources: [.copy("Resources")]
        ),
    ]
)
