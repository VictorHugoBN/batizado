import BatizadoCore
import Foundation
import notify
import os

/// Files in `~/Library/Application Support/Batizado/` shared by the app and the guardian.
public struct SharedState: Sendable {
    /// Posted by the app after it writes or removes the armed record.
    public static let armedChanged = AppInfo.bundleIdentifier + ".armed-changed"
    /// Posted by the guardian after it records why the mode went off.
    public static let shutdownRecorded = AppInfo.bundleIdentifier + ".shutdown-recorded"

    private struct ShutdownNote: Codable {
        let reason: ShutdownReason
    }

    public let directory: URL
    private var armedFile: URL { directory.appending(path: "armed.json") }
    private var shutdownFile: URL { directory.appending(path: "last-shutdown.json") }
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "shared-state")

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        directory = home.appending(
            path: "Library/Application Support/\(AppInfo.name)", directoryHint: .isDirectory)
    }

    public func readArmed() -> ArmedRecord? {
        read(ArmedRecord.self, from: armedFile)
    }

    public func writeArmed(_ record: ArmedRecord) throws {
        try write(record, to: armedFile)
    }

    public func clearArmed() {
        remove(armedFile)
    }

    /// Leaves a newer record alone; the window between the read and the removal is a few microseconds.
    public func clearArmed(ifStill record: ArmedRecord) {
        guard readArmed() == record else { return }
        remove(armedFile)
    }

    public func writeShutdown(_ reason: ShutdownReason) throws {
        try write(ShutdownNote(reason: reason), to: shutdownFile)
    }

    /// Reads the recorded reason and removes it, so it is shown once.
    public func takeShutdown() -> ShutdownReason? {
        guard let note = read(ShutdownNote.self, from: shutdownFile) else { return nil }
        remove(shutdownFile)
        return note.reason
    }

    private func read<Value: Decodable>(_ type: Value.Type, from file: URL) -> Value? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("Ignoring unreadable \(file.path, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func write(_ value: some Encodable, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
    }

    private func remove(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            log.error("Could not remove \(file.path, privacy: .public): \(error, privacy: .public)")
        }
    }
}

public enum DarwinNotification {
    public static func post(_ name: String) {
        notify_post(name)
    }

    /// Calls `handler` on the main queue each time `name` is posted. The registration lives for the process.
    @MainActor
    public static func observe(_ name: String, handler: @escaping @MainActor () -> Void) {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        if status != NOTIFY_STATUS_OK {
            Logger(subsystem: AppInfo.bundleIdentifier, category: "shared-state").error(
                "Could not observe \(name, privacy: .public): \(status)")
        }
    }
}

/// Notify(3) registrations that end when this is released; the owner stores it for as long as it listens.
public final class DarwinSubscription: Sendable {
    private let tokens: [Int32]

    @MainActor
    public init(_ names: [String], handler: @escaping @MainActor () -> Void) {
        tokens = names.compactMap { name in
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            guard status == NOTIFY_STATUS_OK else {
                Logger(subsystem: AppInfo.bundleIdentifier, category: "shared-state").error(
                    "Could not observe \(name, privacy: .public): \(status)")
                return nil
            }
            return token
        }
    }

    deinit {
        for token in tokens { notify_cancel(token) }
    }
}
