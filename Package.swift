// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NumeCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NumeCore", targets: ["NumeCore"]),
    ],
    targets: [
        .target(name: "NumeCore"),
        .testTarget(
            name: "NumeCoreTests",
            dependencies: ["NumeCore"]
        ),
    ]
)
