import BatizadoCore
import Foundation
import notify
import os

/// Files in `~/Library/Application Support/Batizado/` shared by the app and the guardian.
public struct SharedState: Sendable {
    /// Posted by the app after it writes or removes the armed record.
    public static let armedChanged = AppInfo.bundleIdentifier + ".armed-changed"
    /// Posted by the guardian after it acknowledges the armed record.
    public static let acknowledged = AppInfo.bundleIdentifier + ".armed-acknowledged"
    /// Posted by the guardian after it records why the mode went off.
    public static let shutdownRecorded = AppInfo.bundleIdentifier + ".shutdown-recorded"

    private struct ShutdownNote: Codable {
        let reason: ShutdownReason
    }

    public let directory: URL
    private var armedFile: URL { directory.appending(path: "armed.json") }
    private var shutdownFile: URL { directory.appending(path: "last-shutdown.json") }
    private var pendingFile: URL { directory.appending(path: "pending-revert.json") }
    private var acknowledgementFile: URL { directory.appending(path: "acknowledged.json") }
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

    /// Removes the record only if `owner` wrote it, so one copy of the app never drops another's protection.
    public func clearArmed(ownedBy owner: ProcessIdentity) {
        guard readArmed()?.app == owner else { return }
        remove(armedFile)
    }

    /// Leaves a newer record alone; the window between the read and the removal is a few microseconds.
    public func clearArmed(ifStill record: ArmedRecord) {
        guard readArmed() == record else { return }
        remove(armedFile)
    }

    public func readAcknowledgement() -> Acknowledgement? {
        read(Acknowledgement.self, from: acknowledgementFile)
    }

    public func writeAcknowledgement(_ acknowledgement: Acknowledgement) throws {
        try write(acknowledgement, to: acknowledgementFile)
    }

    public func readPendingRevert() -> PendingRevert? {
        read(PendingRevert.self, from: pendingFile)
    }

    public func writePendingRevert(_ pending: PendingRevert) throws {
        try write(pending, to: pendingFile)
    }

    public func clearPendingRevert() {
        remove(pendingFile)
    }

    public func writeShutdown(_ reason: ShutdownReason) throws {
        try write(ShutdownNote(reason: reason), to: shutdownFile)
    }

    /// The recorded reason, left on disk until the app has acted on it and saved the result.
    public func readShutdown() -> ShutdownReason? {
        read(ShutdownNote.self, from: shutdownFile)?.reason
    }

    /// Removes the note once handled; a different reason written in the meantime stays for the next read.
    public func removeShutdown(ifStill reason: ShutdownReason) {
        guard readShutdown() == reason else { return }
        remove(shutdownFile)
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
