import BatizadoCore
import BatizadoSystem
import Darwin
import Dispatch
import os

/// Reacts to events only: its own start, a change of the armed record and the exit of the armed app.
@MainActor
final class GuardianService {
    private let shared = SharedState()
    private var watched: (pid: Int32, source: any DispatchSourceProcess)?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "guardian")

    func start() {
        log.notice("Guardian started")
        DarwinNotification.observe(SharedState.armedChanged) { [weak self] in
            self?.reconcile(on: "armed record changed")
        }
        reconcile(on: "start")
    }

    private func reconcile(on trigger: String) {
        let armed = shared.readArmed()
        let observation = GuardianObservation(
            armed: armed,
            sleepDisabled: SystemFacts.sleepDisabled,
            process: armed.flatMap { SystemFacts.process($0.app.pid) },
            bootTime: SystemFacts.bootTime)
        let effects = BatizadoCore.reconcile(observation)
        log.notice(
            "Reconciled on \(trigger, privacy: .public): armed pid \(armed.map { String($0.app.pid) } ?? "none", privacy: .public), SleepDisabled \(observation.sleepDisabled ? 1 : 0), effects \(String(describing: effects), privacy: .public)"
        )
        for effect in effects {
            guard run(effect) else { break }
        }
    }

    /// False stops the remaining effects, so a failed revert keeps the armed record for the next attempt.
    private func run(_ effect: GuardianEffect) -> Bool {
        switch effect {
        case .watchApp(let pid): watch(pid)
        case .revertSleepDisabled: return revertSleepDisabled()
        case .recordShutdown(let reason):
            do {
                try shared.writeShutdown(reason)
            } catch {
                log.error("Could not record the shutdown reason: \(error, privacy: .public)")
            }
        case .clearArmed(let record): shared.clearArmed(ifStill: record)
        case .signalApp: DarwinNotification.post(SharedState.shutdownRecorded)
        }
        return true
    }

    private func watch(_ pid: Int32) {
        guard watched?.pid != pid else { return }
        watched?.source.cancel()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.appExited(pid) }
        }
        source.resume()
        watched = (pid, source)
        log.notice("Watching app pid \(pid)")
        // The app may have exited before the source was registered.
        if SystemFacts.process(pid) == nil { appExited(pid) }
    }

    private func appExited(_ pid: Int32) {
        guard watched?.pid == pid else { return }
        watched?.source.cancel()
        watched = nil
        reconcile(on: "app pid \(pid) exited")
    }

    // The only command the guardian can run; it has no way to turn the mode on.
    private func revertSleepDisabled() -> Bool {
        let arguments = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
        var argv = arguments.map { strdup($0) } + [nil]
        defer { for arg in argv { free(arg) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, arguments[0], nil, nil, &argv, environ)
        guard spawned == 0 else {
            log.error("Could not run sudo: \(String(cString: strerror(spawned)), privacy: .public)")
            return false
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
        guard exitCode == 0 else {
            log.error("disablesleep 0 failed with status \(exitCode); keeping the armed record")
            return false
        }
        log.notice("disablesleep 0 ran; SleepDisabled is now \(SystemFacts.sleepDisabled ? 1 : 0)")
        return true
    }
}
