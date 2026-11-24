public enum PowerAssertion: Hashable, Sendable, CaseIterable {
    case systemIdle
    case displayIdle
}

public struct Preferences: Hashable, Sendable {
    public var keepAwake: Bool
    public var keepDisplayOn: Bool
    public var lockOnLidClose: Bool
    public var batteryCutoff: Int

    public init(
        keepAwake: Bool = false, keepDisplayOn: Bool = false, lockOnLidClose: Bool = true,
        batteryCutoff: Int = BatteryCutoff.standard
    ) {
        self.keepAwake = keepAwake
        self.keepDisplayOn = keepDisplayOn
        self.lockOnLidClose = lockOnLidClose
        self.batteryCutoff = batteryCutoff
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
}

public struct AppState: Equatable, Sendable {
    public private(set) var preferences: Preferences
    var isRunning = false
    /// The system's `SleepDisabled` as last read by a sensor, never what the app asked for.
    public private(set) var sleepDisabled = false
    public private(set) var helperRule = HelperRuleStatus.notInstalled
    /// What the app last asked `disablesleep` to be in this session; nil until it asks.
    public private(set) var closedLidRequest: Bool?
    public private(set) var notice: Notice?
    /// Why the guardian last turned the mode off, shown until the app quits.
    public private(set) var lastShutdown: ShutdownReason?
    var awaitingHelperRule = false
    /// The armed record is on disk, so the guardian reverts if this process dies.
    var armed = false
    /// Nil until the lid sensor first reports, so a lid already closed at launch is not a closing.
    var lidClosed: Bool?
    var externalDisplay = false
    /// Nil until the power source is first read, and on a Mac without a battery.
    public private(set) var battery: BatteryReading?

    public init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    public var keepAwake: Bool { preferences.keepAwake }
    public var keepDisplayOn: Bool { preferences.keepDisplayOn }
    public var lockOnLidClose: Bool { preferences.lockOnLidClose }
    public var batteryCutoff: Int { preferences.batteryCutoff }

    /// The system's real `SleepDisabled` differs from what the app last asked for.
    public var closedLidDiverged: Bool {
        guard let request = closedLidRequest else { return false }
        return request != sleepDisabled
    }

    var assertions: Set<PowerAssertion> {
        guard isRunning, keepAwake else { return [] }
        return keepDisplayOn ? [.systemIdle, .displayIdle] : [.systemIdle]
    }

    mutating func apply(_ event: AppEvent) -> [Effect] {
        switch event {
        case .launched: isRunning = true
        case .setKeepAwake(let on):
            preferences.keepAwake = on
            if !on, closedLidRequest == true || sleepDisabled { return setClosedLid(false) }
        case .setKeepDisplayOn(let on): preferences.keepDisplayOn = on
        case .setClosedLid(let on):
            let effects = setClosedLid(on)
            guard on, closedLidRefusal == nil else { return effects }
            return effects + [.requestNotificationPermission]
        case .setLockOnLidClose(let on): preferences.lockOnLidClose = on
        case .setBatteryCutoff(let cutoff):
            preferences.batteryCutoff = cutoff
            return armed ? [.updateArmed(batteryCutoff: cutoff)] : []
        case .batteryChanged(let reading): battery = reading
        case .sleepDisabledChanged(let disabled):
            sleepDisabled = disabled
            if !disabled { return disarmIfOff() }
        case .armingFinished(let succeeded): return armingFinished(succeeded: succeeded)
        case .sleepDisabledSwitched(let disabled):
            if !disabled { return disarmIfOff() }
        case .shutdownRecorded(let reason):
            lastShutdown = reason
            if reason.isSticky {
                let effects = setClosedLid(false)
                preferences.keepAwake = false
                return effects + [.notify(reason)]
            }
            guard helperRule == .installed, closedLidRequest != true else { return [] }
            return setClosedLid(true)
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
            return setClosedLid(false) + [.removeHelperRule]
        case .helperRuleRemovalFinished(let outcome):
            switch outcome {
            case .succeeded: helperRule = .notInstalled
            case .cancelled: break
            case .failed(let message): notice = .removeFailed(message)
            }
        case .quit:
            isRunning = false
            awaitingHelperRule = false
            if let request = closedLidRequest, request || sleepDisabled {
                closedLidRequest = false
                return [.setSleepDisabled(false)]
            }
        }
        return []
    }

    /// The lid is closed and no external display is active; nil until the lid sensor first reports.
    private var unattended: Bool? { lidClosed.map { $0 && !externalDisplay } }

    /// Locks on the change into unattended only, so a lid already closed when first read is not a closing.
    private func lockIfLeftUnattended(_ before: Bool?) -> [Effect] {
        guard before == false, unattended == true else { return [] }
        return sleepDisabled && lockOnLidClose ? [.lockScreen] : []
    }

    /// Turning Closed lid on now would only have the low battery protection turn it off again.
    private var closedLidRefusal: Notice? {
        guard let battery, battery.reachesCutoff(batteryCutoff) else { return nil }
        return .batteryLow(percent: battery.percent, cutoff: batteryCutoff)
    }

    private mutating func setClosedLid(_ on: Bool) -> [Effect] {
        notice = nil
        if on, let refusal = closedLidRefusal {
            notice = refusal
            return []
        }
        guard helperRule == .installed else {
            guard on, !awaitingHelperRule else { return [] }
            awaitingHelperRule = true
            return [.installHelperRule]
        }
        guard on || closedLidRequest == true || sleepDisabled else { return [] }
        closedLidRequest = on
        guard on else { return [.setSleepDisabled(false)] }
        preferences.keepAwake = true
        return armed ? [.setSleepDisabled(true)] : [.arm(batteryCutoff: batteryCutoff)]
    }

    private mutating func armingFinished(succeeded: Bool) -> [Effect] {
        guard succeeded else {
            if closedLidRequest == true { closedLidRequest = nil }
            notice = .armFailed
            return []
        }
        armed = true
        return closedLidRequest == true ? [.setSleepDisabled(true)] : disarmIfOff()
    }

    private mutating func disarmIfOff() -> [Effect] {
        guard armed, closedLidRequest != true else { return [] }
        armed = false
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
