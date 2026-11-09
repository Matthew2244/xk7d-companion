// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XK7DCompanion",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "XK7DCore", targets: ["XK7DCore"]),
        .library(name: "XK7DCoreMIDI", targets: ["XK7DCoreMIDI"]),
        .executable(name: "XK7DCompanion", targets: ["XK7DCompanion"]),
    ],
    dependencies: [
        // App updates on the Mac. Exact version: Sparkle's manifest pins its binary by checksum.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Parameter model, MIDI encode/decode, announcements, simulator. No UI, no CoreMIDI:
        // reusable on iPhone as is.
        .target(
            name: "XK7DCore",
            // The table is compiled in (ParameterTable.swift). No SwiftPM resources: Bundle.module only
            // finds them on the Mac that built the app.
            exclude: ["Resources/parameters.json"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CoreMIDI transport and the simulator's virtual MIDI ports. Works on macOS and iOS.
        .target(
            name: "XK7DCoreMIDI",
            dependencies: ["XK7DCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The Mac app (AppKit).
        .executableTarget(
            name: "XK7DCompanion",
            dependencies: ["XK7DCore", "XK7DCoreMIDI", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "XK7DCoreTests",
            dependencies: ["XK7DCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "XK7DIntegrationTests",
            dependencies: ["XK7DCore", "XK7DCoreMIDI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
