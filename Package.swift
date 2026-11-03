// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolvrCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SolvrCore", targets: ["SolvrCore"]),
    ],
    targets: [
        .target(name: "SolvrCore"),
        .testTarget(
            name: "SolvrCoreTests",
            dependencies: ["SolvrCore"]
        ),
    ]
)
