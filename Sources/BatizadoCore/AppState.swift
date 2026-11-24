public enum PowerAssertion: Hashable, Sendable, CaseIterable {
    case systemIdle
    case displayIdle
}

public struct Preferences: Hashable, Sendable {
    public var keepAwake: Bool
    public var keepDisplayOn: Bool

    public init(keepAwake: Bool = false, keepDisplayOn: Bool = false) {
        self.keepAwake = keepAwake
        self.keepDisplayOn = keepDisplayOn
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

    public init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    public var keepAwake: Bool { preferences.keepAwake }
    public var keepDisplayOn: Bool { preferences.keepDisplayOn }

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
        case .setClosedLid(let on): return setClosedLid(on)
        case .sleepDisabledChanged(let disabled):
            sleepDisabled = disabled
            if !disabled { return disarmIfOff() }
        case .armingFinished(let succeeded): return armingFinished(succeeded: succeeded)
        case .sleepDisabledSwitched(let disabled):
            if !disabled { return disarmIfOff() }
        case .shutdownRecorded(let reason):
            lastShutdown = reason
            guard !reason.isSticky, helperRule == .installed, closedLidRequest != true else { return [] }
            return setClosedLid(true)
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

    private mutating func setClosedLid(_ on: Bool) -> [Effect] {
        notice = nil
        guard helperRule == .installed else {
            guard on, !awaitingHelperRule else { return [] }
            awaitingHelperRule = true
            return [.installHelperRule]
        }
        guard on || closedLidRequest == true || sleepDisabled else { return [] }
        closedLidRequest = on
        guard on else { return [.setSleepDisabled(false)] }
        preferences.keepAwake = true
        return armed ? [.setSleepDisabled(true)] : [.arm]
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
