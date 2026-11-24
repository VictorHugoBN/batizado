import BatizadoCore
import BatizadoSystem
import Foundation
import os

@MainActor
protocol GuardianLinking {
    /// Writes a new armed record for this process and tells the guardian; false if it could not be written.
    func arm(batteryCutoff: Int) -> Bool
    /// Rewrites this process's armed record with a new cutoff; the guardian acknowledges it again.
    func updateArmed(batteryCutoff: Int)
    /// Removes the armed record if this process wrote it, and ends any wait or guardian watch.
    func disarm()
    /// Calls `onFinished` once: true when a running guardian acknowledged the current record, false after
    /// `GuardianTiming.acknowledgementWait` seconds. A new wait or a disarm ends this one without a call.
    func awaitAcknowledgement(onFinished: @escaping @MainActor (Bool) -> Void)
    /// `onExit` runs each time the guardian process that acknowledged the current record exits.
    func watchGuardianExit(_ onExit: @escaping @MainActor () -> Void)
    /// Reports a reason the guardian left, at once if one is waiting and again each time it records one. The
    /// note is removed only after `onRecorded` returns, so the handler must have saved what it changed.
    func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void)
    /// Points the guardian's LaunchAgent at this bundle and makes sure launchd has it loaded.
    func installAgent()
}

@MainActor
final class SystemGuardianLink: GuardianLinking {
    private let shared = SharedState()
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "guardian-link")
    /// The record this process wrote last; only an acknowledgement of exactly this one counts.
    private var current: ArmedRecord?
    private var wait: (timer: any DispatchSourceTimer, subscription: DarwinSubscription)?
    private var guardianWatch: (any DispatchSourceProcess)?
    private var onGuardianExit: (@MainActor () -> Void)?

    func arm(batteryCutoff: Int) -> Bool {
        guard let app = SystemFacts.currentProcess else {
            log.error("Could not read this process's start time; not arming")
            return false
        }
        let record = ArmedRecord(
            app: app, bootTime: SystemFacts.bootTime, batteryCutoff: batteryCutoff, id: UUID().uuidString)
        guard write(record) else { return false }
        log.notice("Armed the guardian for pid \(app.pid) with a \(batteryCutoff)% battery cutoff")
        return true
    }

    func updateArmed(batteryCutoff: Int) {
        guard let current else { return }
        let record = ArmedRecord(
            app: current.app, bootTime: current.bootTime, batteryCutoff: batteryCutoff, id: current.id)
        if write(record) { log.notice("Changed the armed battery cutoff to \(batteryCutoff)%") }
    }

    private func write(_ record: ArmedRecord) -> Bool {
        do {
            try shared.writeArmed(record)
        } catch {
            log.error("Could not write the armed record: \(error, privacy: .public)")
            return false
        }
        current = record
        DarwinNotification.post(SharedState.armedChanged)
        return true
    }

    func disarm() {
        endWait()
        guardianWatch?.cancel()
        guardianWatch = nil
        current = nil
        guard let app = SystemFacts.currentProcess else {
            log.error("Could not read this process's start time; leaving the armed record to the guardian")
            return
        }
        shared.clearArmed(ownedBy: app)
        DarwinNotification.post(SharedState.armedChanged)
        log.notice("Disarmed the guardian")
    }

    func awaitAcknowledgement(onFinished: @escaping @MainActor (Bool) -> Void) {
        endWait()
        let finish: @MainActor (Bool) -> Void = { [weak self] received in
            guard let self, self.wait != nil else { return }
            self.endWait()
            let guardian = received ? self.acknowledgingGuardian() : nil
            if let guardian {
                self.log.notice("Guardian pid \(guardian.pid) acknowledged the armed record")
            } else {
                self.log.error(
                    "No running guardian acknowledged the armed record in \(GuardianTiming.acknowledgementWait) s"
                )
            }
            onFinished(received)
            // After the report, so an exit right now reaches the app as a lost guardian, not as nothing.
            if let guardian { self.watch(guardian) }
        }
        let subscription = DarwinSubscription([SharedState.acknowledged]) { [weak self] in
            if self?.acknowledgingGuardian() != nil { finish(true) }
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(GuardianTiming.acknowledgementWait))
        timer.setEventHandler { MainActor.assumeIsolated { finish(false) } }
        timer.resume()
        wait = (timer, subscription)
        // The guardian may have answered before the subscription existed.
        if acknowledgingGuardian() != nil { finish(true) }
    }

    func watchGuardianExit(_ onExit: @escaping @MainActor () -> Void) {
        onGuardianExit = onExit
    }

    /// The guardian that acknowledged exactly the current record, if that same process is still running.
    private func acknowledgingGuardian() -> ProcessIdentity? {
        guard let current, let acknowledgement = shared.readAcknowledgement(),
            acknowledgement.confirms(current, guardianNow: SystemFacts.process(acknowledgement.guardian.pid))
        else { return nil }
        return acknowledgement.guardian
    }

    private func endWait() {
        wait?.timer.cancel()
        wait = nil
    }

    /// A process exit event, not a poll; launchd restarts the guardian, which then acknowledges again.
    private func watch(_ guardian: ProcessIdentity) {
        guardianWatch?.cancel()
        let source = DispatchSource.makeProcessSource(
            identifier: guardian.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.guardianExited(guardian) }
        }
        source.resume()
        guardianWatch = source
        if SystemFacts.process(guardian.pid) != guardian { guardianExited(guardian) }
    }

    private func guardianExited(_ guardian: ProcessIdentity) {
        guard guardianWatch != nil else { return }
        guardianWatch?.cancel()
        guardianWatch = nil
        log.notice("The guardian pid \(guardian.pid) exited; waiting for launchd to start it again")
        onGuardianExit?()
    }

    func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void) {
        let deliver: @MainActor () -> Void = { [shared, log] in
            guard let reason = shared.readShutdown() else { return }
            log.notice("The guardian recorded a shutdown: \(reason.rawValue, privacy: .public)")
            // A crash before this line reads the same note again on the next launch, which is harmless.
            onRecorded(reason)
            shared.removeShutdown(ifStill: reason)
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
