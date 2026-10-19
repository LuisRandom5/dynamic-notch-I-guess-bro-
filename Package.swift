// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DynamicNotch",
            targets: ["DynamicNotch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DynamicNotch",
            path: "Sources/DynamicNotch"
        ),
        // Lógica pura (política de presentación, geometría). Correr con ./scripts/test.sh
        .testTarget(
            name: "DynamicNotchTests",
            dependencies: ["DynamicNotch"],
            path: "Tests/DynamicNotchTests"
        )
    ]
)
