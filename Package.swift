// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AsterMark",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AsterMark", targets: ["AsterMarkApp"]),
        .library(name: "AsterCore", targets: ["AsterCore"]),
    ],
    targets: [
        .target(
            name: "AsterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AsterMarkApp",
            dependencies: ["AsterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AsterCoreTests",
            dependencies: ["AsterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
