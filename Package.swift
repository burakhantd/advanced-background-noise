// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BackgroundSoundsMenu",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "BackgroundSoundsMenu", targets: ["BackgroundSoundsMenu"])
    ],
    targets: [
        .executableTarget(
            name: "BackgroundSoundsMenu",
            path: "Sources/BackgroundSoundsMenu"
        ),
        .testTarget(
            name: "BackgroundSoundsMenuTests",
            dependencies: ["BackgroundSoundsMenu"],
            path: "Tests/BackgroundSoundsMenuTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
