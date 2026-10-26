// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Roue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Roue",
            path: "Sources/Roue"
        ),
        .testTarget(
            name: "RoueTests",
            dependencies: ["Roue"],
            path: "Tests/RoueTests"
        ),
    ]
)
