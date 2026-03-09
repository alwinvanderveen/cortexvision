// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CortexVision",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CortexVision", targets: ["CortexVision"]),
        .executable(name: "CortexVisionApp", targets: ["CortexVisionApp"]),
    ],
    targets: [
        .target(
            name: "CortexVision",
            path: "Sources/CortexVision"
        ),
        .executableTarget(
            name: "CortexVisionApp",
            dependencies: ["CortexVision"],
            path: "CortexVisionApp",
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(
            name: "CortexVisionTests",
            dependencies: ["CortexVision"],
            path: "Tests/CortexVisionTests",
            resources: [.copy("Resources")]
        ),
    ]
)
