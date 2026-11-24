import BatizadoCore
import BatizadoSystem
import Darwin
import Dispatch
import os

/// Reacts to events only: its own start, a change of the armed record, the exit of the armed app, a change
/// of the power source or battery level and a change of the thermal state. There is no timer.
@MainActor
final class GuardianService {
    private let shared = SharedState()
    private var watched: (pid: Int32, source: any DispatchSourceProcess)?
    private var thermal: DarwinSubscription?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "guardian")

    func start() {
        log.notice("Guardian started")
        DarwinNotification.observe(SharedState.armedChanged) { [weak self] in
            self?.reconcile(on: "armed record changed")
        }
        PowerSource.observe { [weak self] in
            self?.reconcile(on: "power source changed")
        }
        thermal = ThermalPressure.observe { [weak self] in
            self?.reconcile(on: "thermal state changed")
        }
        if BuildMode.testMode { log.notice("Debug build: the low battery test mode is available") }
        if BuildMode.testMode { log.notice("Debug build: the thermal test mode is available") }
        reconcile(on: "start")
    }

    private func reconcile(on trigger: String) {
        let armed = shared.readArmed()
        let battery = PowerSource.reading
        let thermal = ThermalPressure.state
        let observation = GuardianObservation(
            armed: armed,
            sleepDisabled: SystemFacts.sleepDisabled,
            process: armed.flatMap { SystemFacts.process($0.app.pid) },
            bootTime: SystemFacts.bootTime,
            battery: battery,
            thermal: thermal,
            testMode: BuildMode.testMode)
        let effects = BatizadoCore.reconcile(observation)
        let batteryText = battery.map { "\($0.percent)% on \($0.onAC ? "AC" : "battery")" } ?? "none"
        let message =
            "Reconciled on \(trigger): armed pid \(armed.map { String($0.app.pid) } ?? "none"), cutoff \(armed.map { "\($0.batteryCutoff)%" } ?? "none"), battery \(batteryText), thermal \(thermal?.rawValue ?? "unknown"), SleepDisabled \(observation.sleepDisabled.sleepDisabledText), effects \(effects)"
        // Battery level changes arrive every few minutes on battery; only the ones that act are worth a notice.
        if trigger == "power source changed",
            effects.allSatisfy({ if case .watchApp = $0 { true } else { false } })
        {
            log.info("\(message, privacy: .public)")
        } else {
            log.notice("\(message, privacy: .public)")
        }
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
        log.notice("disablesleep 0 ran; SleepDisabled is now \(SystemFacts.sleepDisabled.sleepDisabledText)")
        return true
    }
}
