// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OutfitKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OutfitCore", targets: ["OutfitCore"]),
        .library(name: "OutfitKit", targets: ["OutfitKit"]),
    ],
    targets: [
        // Pure Swift logic (geometry, anthropometry, fitting, colour, generator, persistence).
        // Builds and tests on Linux as well as Apple platforms.
        .target(name: "OutfitCore"),
        // Apple-framework layer: Vision, Core ML, Core Graphics, ImageIO.
        .target(name: "OutfitKit", dependencies: ["OutfitCore"]),
        .testTarget(name: "OutfitCoreTests", dependencies: ["OutfitCore"]),
        .testTarget(
            name: "OutfitKitTests",
            dependencies: ["OutfitKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
