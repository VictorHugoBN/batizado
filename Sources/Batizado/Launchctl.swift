import BatizadoCore
import Foundation
import os

/// The user's own LaunchAgents folder and launchd domain; every agent of the app is a plain plist there.
@MainActor
enum UserAgents {
    private static let launchctl = URL(fileURLWithPath: "/bin/launchctl")

    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/LaunchAgents")
    static let domain = "gui/\(getuid())"

    static func file(for agent: LaunchAgent) -> URL { directory.appending(path: agent.fileName) }

    /// This app's bundle path, or nil when it does not run from a .app that will still be there next time.
    static func stableBundlePath(log: Logger) -> String? {
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        guard bundle.pathExtension == "app", !bundle.path.contains("/AppTranslocation/") else {
            log.error("Not running from a stable .app bundle (\(bundle.path, privacy: .public))")
            return nil
        }
        return bundle.path
    }

    static func installed(_ agent: LaunchAgent) -> String? {
        try? String(contentsOf: file(for: agent), encoding: .utf8)
    }

    static func isLoaded(_ agent: LaunchAgent, log: Logger) -> Bool {
        launchctl(["print", "\(domain)/\(agent.label)"], quiet: true, log: log)
    }

    /// Runs one step; false if it failed, which is logged.
    static func perform(_ action: LaunchAgent.Action, _ agent: LaunchAgent, log: Logger) -> Bool {
        let file = file(for: agent)
        switch action {
        case .write:
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try agent.plist.write(to: file, atomically: true, encoding: .utf8)
                log.notice("Wrote \(file.path, privacy: .public) for \(agent.program, privacy: .public)")
                return true
            } catch {
                log.error("Could not write \(file.path, privacy: .public): \(error, privacy: .public)")
                return false
            }
        case .remove:
            do {
                try FileManager.default.removeItem(at: file)
                log.notice("Removed \(file.path, privacy: .public)")
                return true
            } catch {
                log.error("Could not remove \(file.path, privacy: .public): \(error, privacy: .public)")
                return false
            }
        case .unload: return launchctl(["bootout", "\(domain)/\(agent.label)"], log: log)
        case .load: return launchctl(["bootstrap", domain, file.path], log: log)
        }
    }

    /// Fixed executable; the arguments are the user's own domain, a fixed label and the agent path.
    private static func launchctl(_ arguments: [String], quiet: Bool = false, log: Logger) -> Bool {
        let process = Process()
        process.executableURL = launchctl
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
