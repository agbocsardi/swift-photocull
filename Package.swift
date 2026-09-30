// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhotoCull",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PhotoCull", targets: ["PhotoCullApp"]),
        .library(name: "PhotoCullCore", targets: ["PhotoCullCore"]),
        .executable(name: "PhotoCullTests", targets: ["PhotoCullTests"]),
    ],
    targets: [
        .target(name: "PhotoCullCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PhotoCullApp", dependencies: ["PhotoCullCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "PhotoCullTests", dependencies: ["PhotoCullCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
