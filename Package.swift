// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CortexVision",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CortexVision", targets: ["CortexVision"]),
        .executable(name: "CortexVisionApp", targets: ["CortexVisionApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "CortexVision",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources/CortexVision",
            resources: [.copy("Resources")]
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
