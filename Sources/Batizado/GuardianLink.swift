import BatizadoCore
import BatizadoSystem
import Foundation
import os

@MainActor
protocol GuardianLinking {
    /// Writes the armed record for this process and tells the guardian; false if it could not be written.
    func arm(batteryCutoff: Int) -> Bool
    func disarm()
    /// Reports a reason the guardian left, at once if one is waiting and again each time it records one.
    func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void)
    /// Points the guardian's LaunchAgent at this bundle and makes sure launchd has it loaded.
    func installAgent()
}

@MainActor
final class SystemGuardianLink: GuardianLinking {
    private let shared = SharedState()
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "guardian-link")

    func arm(batteryCutoff: Int) -> Bool {
        guard let app = SystemFacts.currentProcess else {
            log.error("Could not read this process's start time; not arming")
            return false
        }
        do {
            try shared.writeArmed(
                ArmedRecord(app: app, bootTime: SystemFacts.bootTime, batteryCutoff: batteryCutoff))
        } catch {
            log.error("Could not write the armed record: \(error, privacy: .public)")
            return false
        }
        DarwinNotification.post(SharedState.armedChanged)
        log.notice("Armed the guardian for pid \(app.pid) with a \(batteryCutoff)% battery cutoff")
        return true
    }

    func disarm() {
        guard let app = SystemFacts.currentProcess else {
            log.error("Could not read this process's start time; leaving the armed record to the guardian")
            return
        }
        shared.clearArmed(ownedBy: app)
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
        guard let bundlePath = UserAgents.stableBundlePath(log: log) else {
            log.error("Guardian not installed")
            return
        }
        let agent = LaunchAgent.guardian(bundlePath: bundlePath)
        guard FileManager.default.isExecutableFile(atPath: agent.program) else {
            log.error("No guardian at \(agent.program, privacy: .public); guardian not installed")
            return
        }
        let actions = LaunchAgent.sync(
            installed: UserAgents.installed(agent), wanted: agent.plist,
            loaded: UserAgents.isLoaded(agent, log: log))
        for action in actions {
            let done = UserAgents.perform(action, agent, log: log)
            if action == .write, !done { return }
            if action == .load, done { log.notice("Loaded the guardian agent") }
        }
    }
}
