// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Batizado",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic shared by the app and the guardian. No AppKit, no IOKit, no process spawning.
        .target(name: "BatizadoCore"),
        // Thin system adapters both executables need: shared state files, process identity, SleepDisabled.
        .target(name: "BatizadoSystem", dependencies: ["BatizadoCore"]),
        // Menu bar app.
        .executableTarget(name: "Batizado", dependencies: ["BatizadoCore", "BatizadoSystem"]),
        // User-level watchdog that reverts `disablesleep` when the app cannot.
        .executableTarget(name: "BatizadoGuardian", dependencies: ["BatizadoCore", "BatizadoSystem"]),
        .testTarget(name: "BatizadoCoreTests", dependencies: ["BatizadoCore"]),
    ]
)
