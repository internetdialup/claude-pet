// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudePet", targets: ["ClaudePet"])
    ],
    // Intentionally empty. Bamboo.md §6 claims no network egress; a dependency-free
    // graph is what makes that claim verifiable rather than promised.
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClaudePet",
            path: "Sources/ClaudePet",
            exclude: ["Support/Info.plist"],
            // The hook shim ships as a resource so the shell script on disk is
            // its only home. It was previously duplicated as a Swift string
            // literal, which is two sources of truth for one file.
            resources: [.copy("Resources/claude-pet-hook.sh")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClaudePetTests",
            dependencies: ["ClaudePet"],
            path: "Tests/ClaudePetTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
