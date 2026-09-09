// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AmbientSounds",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AmbientSounds", targets: ["AmbientSounds"])
    ],
    targets: [
        .executableTarget(
            name: "AmbientSounds",
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
