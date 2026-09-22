// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CargoRemoteKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CargoRemoteKit", targets: ["CargoRemoteKit"])
    ],
    targets: [
        .target(name: "CargoRemoteKit"),
        .testTarget(name: "CargoRemoteKitTests", dependencies: ["CargoRemoteKit"])
    ]
)
