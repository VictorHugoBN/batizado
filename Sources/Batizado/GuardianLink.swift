import BatizadoCore
import BatizadoSystem
import Foundation
import os

@MainActor
protocol GuardianLinking {
    /// Writes the armed record for this process and tells the guardian; false if it could not be written.
    func arm() -> Bool
    func disarm()
    /// Reports a reason the guardian left, at once if one is waiting and again each time it records one.
    func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void)
    /// Points the guardian's LaunchAgent at this bundle and makes sure launchd has it loaded.
    func installAgent()
}

@MainActor
final class SystemGuardianLink: GuardianLinking {
    private static let launchctl = URL(fileURLWithPath: "/bin/launchctl")

    private let shared = SharedState()
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "guardian-link")

    func arm() -> Bool {
        guard let app = SystemFacts.currentProcess else {
            log.error("Could not read this process's start time; not arming")
            return false
        }
        do {
            try shared.writeArmed(ArmedRecord(app: app, bootTime: SystemFacts.bootTime))
        } catch {
            log.error("Could not write the armed record: \(error, privacy: .public)")
            return false
        }
        DarwinNotification.post(SharedState.armedChanged)
        log.notice("Armed the guardian for pid \(app.pid)")
        return true
    }

    func disarm() {
        shared.clearArmed()
        DarwinNotification.post(SharedState.armedChanged)
        log.notice("Disarmed the guardian")
    }

    func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void) {
        let deliver: @MainActor () -> Void = { [shared, log] in
            guard let reason = shared.takeShutdown() else { return }
            log.notice("The guardian recorded a shutdown: \(reason.rawValue, privacy: .public)")
            onRecorded(reason)
        }
        DarwinNotification.observe(SharedState.shutdownRecorded, handler: deliver)
        deliver()
    }

    func installAgent() {
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        guard bundle.pathExtension == "app", !bundle.path.contains("/AppTranslocation/") else {
            log.error(
                "Not running from a stable .app bundle (\(bundle.path, privacy: .public)); guardian not installed"
            )
            return
        }
        let agent = LaunchAgent.guardian(bundlePath: bundle.path)
        guard FileManager.default.isExecutableFile(atPath: agent.program) else {
            log.error("No guardian at \(agent.program, privacy: .public); guardian not installed")
            return
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/LaunchAgents")
        let file = directory.appending(path: agent.fileName)
        let domain = "gui/\(getuid())"
        let installed = try? String(contentsOf: file, encoding: .utf8)
        let loaded = launchctl("print", "\(domain)/\(agent.label)", quiet: true)
        for action in LaunchAgent.sync(installed: installed, wanted: agent.plist, loaded: loaded) {
            switch action {
            case .write:
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try agent.plist.write(to: file, atomically: true, encoding: .utf8)
                    log.notice("Wrote \(file.path, privacy: .public) for \(agent.program, privacy: .public)")
                } catch {
                    log.error("Could not write \(file.path, privacy: .public): \(error, privacy: .public)")
                    return
                }
            case .unload: _ = launchctl("bootout", "\(domain)/\(agent.label)")
            case .load:
                if launchctl("bootstrap", domain, file.path) { log.notice("Loaded the guardian agent") }
            }
        }
    }

    /// Fixed executable; the arguments are the user's own domain, the fixed label and the agent path.
    private func launchctl(_ arguments: String..., quiet: Bool = false) -> Bool {
        let process = Process()
        process.executableURL = Self.launchctl
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            log.error("Could not run launchctl: \(error, privacy: .public)")
            return false
        }
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0, !quiet {
            log.error(
                "launchctl \(arguments.joined(separator: " "), privacy: .public) failed (\(process.terminationStatus)): \(message, privacy: .public)"
            )
        }
        return process.terminationStatus == 0
    }
}
