import BatizadoCore
import Foundation
import os

@MainActor
protocol SleepDisabledSwitching {
    /// Runs one of the two commands the helper rule allows; true when it exited cleanly.
    func set(_ disabled: Bool) -> Bool
}

@MainActor
struct SudoSleepDisabledSwitch: SleepDisabledSwitching {
    private static let sudo = URL(fileURLWithPath: "/usr/bin/sudo")
    // Fixed arguments matching HelperRule.commands; -n makes sudo fail instead of prompting.
    private static let turnOn = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
    private static let turnOff = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]

    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "sleep-disabled")

    func set(_ disabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = Self.sudo
        process.arguments = disabled ? Self.turnOn : Self.turnOff
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            log.error("Could not run sudo: \(error.localizedDescription, privacy: .public)")
            return false
        }
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            log.error(
                "disablesleep \(disabled ? 1 : 0) failed (\(process.terminationStatus)): \(message, privacy: .public)"
            )
            return false
        }
        log.info("disablesleep \(disabled ? 1 : 0) ran")
        return true
    }
}
