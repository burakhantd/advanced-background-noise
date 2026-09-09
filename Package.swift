// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AmbientSounds",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AmbientSounds", targets: ["AmbientSounds"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "AmbientSounds",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AmbientSounds"
        ),
        .testTarget(
            name: "AmbientSoundsTests",
            dependencies: ["AmbientSounds"],
            path: "Tests/AmbientSoundsTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
