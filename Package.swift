// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TopGunSimulator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TopGunSimulator", targets: ["TopGunSimulator"]),
        .library(name: "FlightCore", targets: ["FlightCore"]),
    ],
    targets: [
        .target(name: "FlightCore"),
        .executableTarget(name: "TopGunSimulator", dependencies: ["FlightCore"]),
        .testTarget(name: "FlightCoreTests", dependencies: ["FlightCore"]),
    ]
)
