// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "uttr-bench",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.6.1")
    ],
    targets: [
        .executableTarget(
            name: "bench",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
