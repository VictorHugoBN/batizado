import BatizadoCore
import BatizadoSystem
import Darwin
import Dispatch
import os

/// Reacts to events only: its own start, a change of the armed record, the exit of the armed app, a change
/// of the power source or battery level and a change of the thermal state. The only timer is the retry of a
/// revert that failed, which exists while that revert is pending, and one recheck a few seconds after the
/// record of a dead app was cleared.
@MainActor
final class GuardianService {
    private let shared = SharedState()
    private var watched: (pid: Int32, source: any DispatchSourceProcess)?
    private var thermal: DarwinSubscription?
    private var retry: (any DispatchSourceTimer)?
    private var graceCheck: (any DispatchSourceTimer)?
    private var failedAttempts = 0
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

    private func observe() -> GuardianObservation {
        let armed = shared.readArmed()
        return GuardianObservation(
            armed: armed,
            sleepDisabled: SystemFacts.sleepDisabled,
            process: armed.flatMap { SystemFacts.process($0.app.pid) },
            bootTime: SystemFacts.bootTime,
            battery: PowerSource.reading,
            thermal: ThermalPressure.state,
            testMode: BuildMode.testMode,
            pending: shared.readPendingRevert())
    }

    private func reconcile(on trigger: String) {
        let observation = observe()
        let effects = BatizadoCore.reconcile(observation)
        let armed = observation.armed
        let batteryText =
            observation.battery.map { "\($0.percent)% on \($0.onAC ? "AC" : "battery")" } ?? "none"
        let message =
            "Reconciled on \(trigger): armed pid \(armed.map { String($0.app.pid) } ?? "none"), cutoff \(armed.map { "\($0.batteryCutoff)%" } ?? "none"), battery \(batteryText), thermal \(observation.thermal?.rawValue ?? "unknown"), pending \(observation.pending.map { $0.reason.rawValue } ?? "none"), SleepDisabled \(observation.sleepDisabled.sleepDisabledText), effects \(effects)"
        // Battery level changes arrive every few minutes on battery; only the ones that act are worth a notice.
        if trigger == "power source changed",
            effects.allSatisfy({ if case .watchApp = $0 { true } else { false } })
        {
            log.info("\(message, privacy: .public)")
        } else {
            log.notice("\(message, privacy: .public)")
        }
        perform(effects)
    }

    private func recheck(afterClearing record: ArmedRecord) {
        let observation = observe()
        let effects = BatizadoCore.recheck(afterClearing: record, observation)
        log.notice(
            "Rechecked after clearing pid \(record.app.pid): armed pid \(observation.armed.map { String($0.app.pid) } ?? "none"), SleepDisabled \(observation.sleepDisabled.sleepDisabledText), effects \(effects)"
        )
        perform(effects)
    }

    private func perform(_ effects: [GuardianEffect]) {
        for effect in effects where !run(effect) {
            scheduleRetry()
            return
        }
        guard effects.contains(.clearPending) else { return }
        cancelRetry()
        // A newer armed record may have waited behind the pending revert.
        reconcile(on: "pending revert done")
    }

    /// One shot; the dead app's `disablesleep 1` takes well under a second to land if it was on its way.
    private func scheduleRecheck(afterClearing record: ArmedRecord) {
        graceCheck?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(GuardianTiming.recheckGrace))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.graceCheck = nil
                self?.recheck(afterClearing: record)
            }
        }
        source.resume()
        graceCheck = source
    }

    /// One shot, longer after each failure; the pending revert on disk survives a restart in between.
    private func scheduleRetry() {
        guard retry == nil else { return }
        failedAttempts += 1
        let delay = RevertRetry.delay(afterFailures: failedAttempts)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(delay))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.retry = nil
                self?.reconcile(on: "retry \(self?.failedAttempts ?? 0)")
            }
        }
        source.resume()
        retry = source
        log.notice("The revert did not finish; trying again in \(delay) s")
    }

    private func cancelRetry() {
        retry?.cancel()
        retry = nil
        failedAttempts = 0
    }

    /// False stops the remaining effects, so a failed revert keeps the armed record and the pending revert.
    private func run(_ effect: GuardianEffect) -> Bool {
        switch effect {
        case .watchApp(let pid): watch(pid)
        case .markPending(let pending):
            do {
                try shared.writePendingRevert(pending)
            } catch {
                log.error("Could not store the pending revert: \(error, privacy: .public)")
            }
        case .clearPending: shared.clearPendingRevert()
        case .revertSleepDisabled: return revertSleepDisabled()
        case .recordShutdown(let reason):
            do {
                try shared.writeShutdown(reason)
            } catch {
                // Clearing the record without the note would let the app restore after a protection.
                log.error(
                    "Could not record the shutdown reason; keeping the armed record: \(error, privacy: .public)"
                )
                return false
            }
        case .clearArmed(let record): shared.clearArmed(ifStill: record)
        case .signalApp: DarwinNotification.post(SharedState.shutdownRecorded)
        case .recheckAfterGrace(let record): scheduleRecheck(afterClearing: record)
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
            log.error("disablesleep 0 failed with status \(exitCode); keeping the revert pending")
            return false
        }
        log.notice("disablesleep 0 ran; SleepDisabled is now \(SystemFacts.sleepDisabled.sleepDisabledText)")
        return true
    }
}
