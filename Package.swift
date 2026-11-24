// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Batizado",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic shared by the app and the guardian. No AppKit, no IOKit, no process spawning.
        .target(name: "BatizadoCore"),
        // Menu bar app.
        .executableTarget(name: "Batizado", dependencies: ["BatizadoCore"]),
        // User-level watchdog that reverts `disablesleep` when the app cannot.
        .executableTarget(name: "BatizadoGuardian", dependencies: ["BatizadoCore"]),
        .testTarget(name: "BatizadoCoreTests", dependencies: ["BatizadoCore"]),
    ]
)
