// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Earshot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EarshotKit", targets: ["EarshotKit"]),
        // Product name differs from the .app bundle name on purpose: macOS
        // filesystems are case-insensitive, so an executable named "Earshot"
        // would collide with the "earshot" CLI in the same build directory.
        .executable(name: "EarshotApp", targets: ["EarshotApp"]),
        .executable(name: "earshot", targets: ["EarshotCLI"]),
    ],
    targets: [
        .target(
            name: "EarshotKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .executableTarget(
            name: "EarshotApp",
            dependencies: ["EarshotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "EarshotCLI",
            dependencies: ["EarshotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EarshotKitTests",
            dependencies: ["EarshotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
