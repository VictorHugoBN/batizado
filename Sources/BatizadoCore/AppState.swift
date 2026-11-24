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

public struct AppState: Equatable, Sendable {
    public private(set) var preferences: Preferences
    var isRunning = false
    /// The system's `SleepDisabled` as last read by a sensor, never what the app asked for.
    public private(set) var sleepDisabled = false

    public init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    public var keepAwake: Bool { preferences.keepAwake }
    public var keepDisplayOn: Bool { preferences.keepDisplayOn }

    var assertions: Set<PowerAssertion> {
        guard isRunning, keepAwake else { return [] }
        return keepDisplayOn ? [.systemIdle, .displayIdle] : [.systemIdle]
    }

    mutating func apply(_ event: AppEvent) {
        switch event {
        case .launched: isRunning = true
        case .setKeepAwake(let on): preferences.keepAwake = on
        case .setKeepDisplayOn(let on): preferences.keepDisplayOn = on
        case .sleepDisabledChanged(let disabled): sleepDisabled = disabled
        case .quit: isRunning = false
        }
    }
}
