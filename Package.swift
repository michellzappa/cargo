// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cargo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Cargo", targets: ["Cargo"])
    ],
    targets: [
        .executableTarget(
            name: "Cargo",
            path: "Sources/Cargo"
        ),
        .testTarget(
            name: "CargoTests",
            dependencies: ["Cargo"],
            path: "Tests/CargoTests"
        )
    ]
)
