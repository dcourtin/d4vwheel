// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "d4vWheel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "d4vWheel",
            path: "Sources/d4vWheel"
        ),
        .testTarget(
            name: "d4vWheelTests",
            dependencies: ["d4vWheel"],
            path: "Tests/d4vWheelTests"
        ),
    ]
)
