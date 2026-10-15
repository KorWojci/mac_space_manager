// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSpaceManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacSpaceManager", targets: ["MacSpaceManager"]),
        .library(name: "SpaceCore", targets: ["SpaceCore"]),
    ],
    targets: [
        // Platform-independent scanning, layout, categorization and deletion logic.
        .target(name: "SpaceCore"),
        // SwiftUI macOS application.
        .executableTarget(name: "MacSpaceManager", dependencies: ["SpaceCore"]),
        .testTarget(name: "SpaceCoreTests", dependencies: ["SpaceCore"]),
    ]
)
