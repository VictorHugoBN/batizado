public enum PowerAssertion: Hashable, Sendable, CaseIterable {
    case systemIdle
    case displayIdle
}

public struct Preferences: Hashable, Sendable {
    public var keepAwake: Bool
    /// The user left Closed lid on: kept by Quit and a crash, cleared by turning it off and by a sticky reason.
    public var closedLid: Bool
    public var keepDisplayOn: Bool
    public var lockOnLidClose: Bool
    public var batteryCutoff: Int
    public var autoTurnOff: AutoTurnOff
    /// When the timer turns everything off; stored as an instant so a restart keeps the same end.
    public var timerDeadline: Instant?

    public init(
        keepAwake: Bool = false, closedLid: Bool = false, keepDisplayOn: Bool = false,
        lockOnLidClose: Bool = true,
        batteryCutoff: Int = BatteryCutoff.standard, autoTurnOff: AutoTurnOff = .never,
        timerDeadline: Instant? = nil
    ) {
        self.keepAwake = keepAwake
        self.closedLid = closedLid
        self.keepDisplayOn = keepDisplayOn
        self.lockOnLidClose = lockOnLidClose
        self.batteryCutoff = batteryCutoff
        self.autoTurnOff = autoTurnOff
        self.timerDeadline = timerDeadline
    }
}

public enum HelperRuleStatus: Equatable, Sendable {
    case notInstalled
    case installed
    /// Was installed in this session and is gone, so it was removed from outside the app.
    case missing
}

/// How a step behind the administrator password window ended.
public enum AdministratorOutcome: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(String)
}

public enum Notice: Equatable, Sendable {
    case installFailed(String)
    case removeFailed(String)
    /// The armed record could not be written, so Closed lid stayed off.
    case armFailed
    /// Closed lid stayed off because the low battery protection would turn it off at once.
    case batteryLow(percent: Int, cutoff: Int)
    /// Closed lid stayed off because the thermal protection would turn it off at once.
    case overheated(ThermalState)
    /// Closed lid was left on but not turned back on at launch: the helper rule is not installed.
    case notRestored
    /// Closed lid stayed off: no running guardian acknowledged the armed record in time.
    case guardianNotRunning
    /// Closed lid was turned off: the guardian exited and none came back in time.
    case guardianLost
    /// "Remove helper rule" kept the rule: Closed lid could not be turned off first.
    case ruleKept
}

/// Why the app is waiting for a guardian's acknowledgement.
enum GuardianWait: Equatable, Sendable {
    /// Before `disablesleep` goes on.
    case arming
    /// With the mode on, after the guardian that acknowledged it exited.
    case reacquiring
}

public struct AppState: Equatable, Sendable {
    public private(set) var preferences: Preferences
    var isRunning = false
    /// The system's `SleepDisabled` as last read by a sensor, never what the app asked for; nil until read and
    /// when the read failed.
    public private(set) var sleepDisabled: Bool?
    public private(set) var helperRule = HelperRuleStatus.notInstalled
    /// What the app last asked `disablesleep` to be in this session; nil until it asks.
    public private(set) var closedLidRequest: Bool?
    public private(set) var notice: Notice?
    /// Why the guardian last turned the mode off, shown until the app quits.
    public private(set) var lastShutdown: ShutdownReason?
    var awaitingHelperRule = false
    /// "Remove helper rule" waits for `SleepDisabled` to read 0: without the rule nothing could turn it off.
    var removingHelperRule = false
    /// The armed record is on disk, so the guardian reverts if this process dies.
    var armed = false
    /// A live guardian acknowledged the armed record; `disablesleep` goes on only after this.
    var acknowledged = false
    var guardianWait: GuardianWait?
    /// Nil until the lid sensor first reports, so a lid already closed at launch is not a closing.
    var lidClosed: Bool?
    var externalDisplay = false
    /// Nil until the power source is first read, and on a Mac without a battery.
    public private(set) var battery: BatteryReading?
    /// Nil until the thermal state is first read.
    public private(set) var thermal: ThermalState?
    /// The deadline the warning was posted for, so an extended deadline is warned about again.
    var warnedDeadline: Instant?
    /// The launch restore has run, so a later crash or restart report re-applies the user's intention.
    var restored = false

    public init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    public var keepAwake: Bool { preferences.keepAwake }
    /// Closed lid was asked for and waits for the guardian to take charge.
    public var awaitingGuardian: Bool { guardianWait == .arming }
    public var keepDisplayOn: Bool { preferences.keepDisplayOn }
    public var lockOnLidClose: Bool { preferences.lockOnLidClose }
    public var batteryCutoff: Int { preferences.batteryCutoff }
    public var autoTurnOff: AutoTurnOff { preferences.autoTurnOff }
    public var timerDeadline: Instant? { preferences.timerDeadline }

    /// The system's real `SleepDisabled` differs from what the app last asked for.
    public var closedLidDiverged: Bool {
        guard let request = closedLidRequest else { return false }
        return request != sleepDisabled
    }

    /// The next instant the app must send `clockTicked` at: the warning, then the end; nil without a timer.
    public var nextTimerCheck: Instant? {
        guard let deadline = timerDeadline else { return nil }
        return warnedDeadline == deadline ? deadline : deadline - AutoTurnOff.warningLead
    }

    var assertions: Set<PowerAssertion> {
        guard isRunning, keepAwake else { return [] }
        return keepDisplayOn ? [.systemIdle, .displayIdle] : [.systemIdle]
    }

    mutating func apply(_ event: AppEvent, at now: Instant) -> [Effect] {
        let effects = handle(event, at: now)
        keepTimerInStep(at: now)
        return effects
    }

    /// While the mode is on with a duration chosen there is a deadline; while it is off there is none.
    private mutating func keepTimerInStep(at now: Instant) {
        guard keepAwake else {
            preferences.timerDeadline = nil
            return
        }
        if preferences.timerDeadline == nil {
            preferences.timerDeadline = autoTurnOff.deadline(from: now)
        }
    }

    private mutating func handle(_ event: AppEvent, at now: Instant) -> [Effect] {
        switch event {
        case .launched: isRunning = true
        case .setKeepAwake(let on):
            preferences.keepAwake = on
            if !on { preferences.closedLid = false }
            if !on, closedLidRequest == true || sleepDisabled != false { return setClosedLid(false) }
        case .setKeepDisplayOn(let on): preferences.keepDisplayOn = on
        case .setClosedLid(let on):
            let effects = setClosedLid(on)
            guard on, closedLidRefusal == nil else { return effects }
            return effects + [.requestNotificationPermission]
        case .setLockOnLidClose(let on): preferences.lockOnLidClose = on
        case .setAutoTurnOff(let duration):
            preferences.autoTurnOff = duration
            preferences.timerDeadline = keepAwake ? duration.deadline(from: now) : nil
            return duration == .never ? [] : [.requestNotificationPermission]
        case .restore:
            restored = true
            return restoreClosedLid()
        case .clockTicked: return checkTimer(at: now)
        case .extendTimer:
            guard let deadline = timerDeadline else { return [] }
            guard now < deadline else { return turnEverythingOff(because: .timer) }
            preferences.timerDeadline = deadline + AutoTurnOff.extensionLength
        case .setBatteryCutoff(let cutoff):
            preferences.batteryCutoff = cutoff
            return armed ? [.updateArmed(batteryCutoff: cutoff)] : []
        case .batteryChanged(let reading): battery = reading
        case .thermalChanged(let state): thermal = state
        case .sleepDisabledChanged(let disabled):
            sleepDisabled = disabled
            return (disabled == false ? disarmIfOff() : []) + continueRuleRemoval(settled: false)
        case .sleepDisabledSettled(let disabled):
            sleepDisabled = disabled
            return (disabled == false ? disarmIfOff() : []) + continueRuleRemoval(settled: true)
        case .armingFinished(let succeeded): return armingFinished(succeeded: succeeded)
        case .acknowledgementFinished(let received): return acknowledgementFinished(received: received)
        case .guardianExited:
            guard armed, acknowledged else { return [] }
            acknowledged = false
            guardianWait = .reacquiring
            return [.awaitAcknowledgement]
        case .sleepDisabledSwitched(let disabled):
            if !disabled { return disarmIfOff() }
        case .shutdownRecorded(let reason):
            if reason.isSticky { return turnEverythingOff(because: reason) }
            // The timer already ended at launch; the crash before it must not turn the mode back on.
            if lastShutdown?.isSticky == true { return [] }
            lastShutdown = reason
            // A late report means the guardian may have reverted after the restore; put the intention back.
            return restored ? restoreClosedLid() : []
        case .lidChanged(let closed):
            let before = unattended
            lidClosed = closed
            return lockIfLeftUnattended(before)
        case .externalDisplayChanged(let active):
            let before = unattended
            externalDisplay = active
            return lockIfLeftUnattended(before)
        case .helperRuleChecked(let installed): ruleChecked(installed: installed)
        case .reinstallHelperRule:
            notice = nil
            return [.installHelperRule]
        case .helperRuleInstallFinished(let outcome): return installFinished(outcome)
        case .removeHelperRule:
            notice = nil
            awaitingHelperRule = false
            let effects = setClosedLid(false)
            if sleepDisabled == false, !effects.contains(.setSleepDisabled(false)) {
                return effects + [.removeHelperRule]
            }
            removingHelperRule = true
            return effects
        case .helperRuleRemovalFinished(let outcome):
            switch outcome {
            case .succeeded: helperRule = .notInstalled
            case .cancelled: break
            case .failed(let message): notice = .removeFailed(message)
            }
        case .quit:
            isRunning = false
            awaitingHelperRule = false
            if let request = closedLidRequest, request || sleepDisabled != false {
                closedLidRequest = false
                return [.setSleepDisabled(false)]
            }
        }
        return []
    }

    /// A protection or the timer: Closed lid and Keep awake go off and stay off on the next launch.
    private mutating func turnEverythingOff(because reason: ShutdownReason) -> [Effect] {
        // The same note read again (the app stopped before removing it) has nothing left to tell.
        let repeated = lastShutdown == reason && !keepAwake && closedLidRequest != true
        lastShutdown = reason
        let effects = setClosedLid(false)
        preferences.keepAwake = false
        return effects + (repeated ? [] : [.notify(reason)])
    }

    private mutating func checkTimer(at now: Instant) -> [Effect] {
        guard let deadline = timerDeadline else { return [] }
        if now >= deadline { return turnEverythingOff(because: .timer) }
        guard warnedDeadline != deadline,
            now >= deadline - AutoTurnOff.warningLead
        else { return [] }
        warnedDeadline = deadline
        return [.warnTimer(deadline: deadline)]
    }

    /// The lid is closed and no external display is active; nil until the lid sensor first reports.
    private var unattended: Bool? { lidClosed.map { $0 && !externalDisplay } }

    /// Locks on the change into unattended only, so a lid already closed when first read is not a closing.
    private func lockIfLeftUnattended(_ before: Bool?) -> [Effect] {
        guard before == false, unattended == true else { return [] }
        return sleepDisabled == true && lockOnLidClose ? [.lockScreen] : []
    }

    /// Turning Closed lid on now would only have a protection turn it off again; heat is checked first, as in
    /// the guardian.
    private var closedLidRefusal: Notice? {
        if let thermal, thermal.isOverheated { return .overheated(thermal) }
        guard let battery, battery.reachesCutoff(batteryCutoff) else { return nil }
        return .batteryLow(percent: battery.percent, cutoff: batteryCutoff)
    }

    /// Re-applies the Closed lid the user left on; one that cannot go on now is dropped and explained, and the
    /// password window never opens for it.
    private mutating func restoreClosedLid() -> [Effect] {
        guard preferences.closedLid else { return [] }
        guard helperRule == .installed else {
            preferences.closedLid = false
            notice = .notRestored
            return []
        }
        return setClosedLid(true)
    }

    private mutating func setClosedLid(_ on: Bool) -> [Effect] {
        notice = nil
        if on { removingHelperRule = false }
        if !on { preferences.closedLid = false }
        if on, let refusal = closedLidRefusal {
            preferences.closedLid = false
            notice = refusal
            return []
        }
        guard helperRule == .installed else {
            guard on, !awaitingHelperRule else { return [] }
            awaitingHelperRule = true
            return [.installHelperRule]
        }
        guard on || closedLidRequest == true || sleepDisabled != false else { return [] }
        closedLidRequest = on
        guard on else { return [.setSleepDisabled(false)] }
        preferences.closedLid = true
        preferences.keepAwake = true
        guard armed else { return [.arm(batteryCutoff: batteryCutoff)] }
        if acknowledged { return [.setSleepDisabled(true)] }
        // A wait already running ends in the turn on; otherwise start one.
        let waiting = guardianWait != nil
        guardianWait = .arming
        return waiting ? [] : [.awaitAcknowledgement]
    }

    private mutating func armingFinished(succeeded: Bool) -> [Effect] {
        guard succeeded else {
            if closedLidRequest == true {
                closedLidRequest = nil
                preferences.closedLid = false
            }
            notice = .armFailed
            return []
        }
        armed = true
        acknowledged = false
        guard closedLidRequest == true else { return disarmIfOff() }
        guardianWait = .arming
        return [.awaitAcknowledgement]
    }

    private mutating func acknowledgementFinished(received: Bool) -> [Effect] {
        guard let wait = guardianWait else { return [] }
        guardianWait = nil
        if received {
            acknowledged = true
            guard wait == .arming else { return [] }
            return closedLidRequest == true ? [.setSleepDisabled(true)] : disarmIfOff()
        }
        // No guardian would turn the mode off if this process died, so it must not be on.
        let effects: [Effect]
        if sleepDisabled == false {
            closedLidRequest = nil
            preferences.closedLid = false
            armed = false
            effects = [.disarm]
        } else {
            effects = setClosedLid(false)
        }
        notice = wait == .arming ? .guardianNotRunning : .guardianLost
        return effects
    }

    /// The rule goes only after a read of 0; the settled read after the turn off ends the wait either way.
    private mutating func continueRuleRemoval(settled: Bool) -> [Effect] {
        guard removingHelperRule else { return [] }
        if sleepDisabled == false {
            removingHelperRule = false
            return [.removeHelperRule]
        }
        if settled {
            removingHelperRule = false
            notice = .ruleKept
        }
        return []
    }

    private mutating func disarmIfOff() -> [Effect] {
        guard armed, closedLidRequest != true else { return [] }
        armed = false
        acknowledged = false
        guardianWait = nil
        return [.disarm]
    }

    private mutating func ruleChecked(installed: Bool) {
        if installed {
            helperRule = .installed
        } else if helperRule == .installed {
            helperRule = .missing
        }
    }

    private mutating func installFinished(_ outcome: AdministratorOutcome) -> [Effect] {
        let wanted = awaitingHelperRule
        awaitingHelperRule = false
        switch outcome {
        case .succeeded:
            helperRule = .installed
            return wanted ? setClosedLid(true) : []
        case .cancelled: return []
        case .failed(let message):
            notice = .installFailed(message)
            return []
        }
    }
}
