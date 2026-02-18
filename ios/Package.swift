// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReactNativeLlmMediapipe",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ReactNativeLlmMediapipe",
            targets: ["ReactNativeLlmMediapipe"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.0")
    ],
    targets: [
        .target(
            name: "ReactNativeLlmMediapipe",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLM", package: "mlx-swift-examples"),
                .product(name: "MLXRandom", package: "mlx-swift")
            ],
            path: "."
        )
    ]
)