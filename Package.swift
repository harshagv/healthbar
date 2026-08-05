// swift-tools-version:5.9
import PackageDescription

// One package, one app per directory under apps/.
//
//   apps/<Name>/Sources/      Swift sources (+ any SwiftPM resources)
//   apps/<Name>/Resources/    Info.plist and AppIcon.icns, consumed by build.sh
//   apps/<Name>/Art/          master art that is processed, not shipped
//
// Shared tooling (build.sh, Makefile, scripts/, CI) lives at the repo root and
// is generic over the app name, so adding an app means adding a directory and
// one target here.
let package = Package(
    name: "Upright",
    platforms: [
        .macOS(.v14)
    ],
    // Declared explicitly so `swift build --product <name>` builds a single app
    // instead of every target in the package.
    products: [
        .executable(name: "Upright", targets: ["Upright"]),
        .executable(name: "MiniMe", targets: ["MiniMe"])
    ],
    targets: [
        .executableTarget(
            name: "Upright",
            path: "apps/Upright/Sources"
        ),
        .executableTarget(
            name: "MiniMe",
            path: "apps/MiniMe/Sources",
            // Frames generated from apps/MiniMe/Art/source.png by
            // scripts/slice_sprites.swift. `.copy` keeps the folder intact so
            // they load by subdirectory rather than a flattened namespace.
            resources: [.copy("Sprites")]
        )
    ]
)
