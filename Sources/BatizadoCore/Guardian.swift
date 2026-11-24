/// Why the mode was turned off. Sticky reasons keep it off on the next launch.
public enum ShutdownReason: String, Codable, Equatable, Sendable, CaseIterable {
    case user
    case quit
    case battery
    case thermal
    case timer
    case appDied
    case reboot

    public var isSticky: Bool {
        switch self {
        case .battery, .thermal, .timer: true
        case .user, .quit, .appDied, .reboot: false
        }
    }
}

/// A process told apart from any later one that reuses its pid.
public struct ProcessIdentity: Codable, Equatable, Sendable {
    public let pid: Int32
    /// Process start time in microseconds since 1970.
    public let startedAt: Int64

    public init(pid: Int32, startedAt: Int64) {
        self.pid = pid
        self.startedAt = startedAt
    }
}

/// Written by the app before it turns `disablesleep` on; the guardian only reverts what this record claims.
public struct ArmedRecord: Codable, Equatable, Sendable {
    public let app: ProcessIdentity
    /// `kern.boottime` in seconds when the app armed, to tell a restart from a crash.
    public let bootTime: Int64
    /// The low battery cutoff in percent, rewritten when the user changes it while armed.
    public let batteryCutoff: Int

    public init(app: ProcessIdentity, bootTime: Int64, batteryCutoff: Int) {
        self.app = app
        self.bootTime = bootTime
        self.batteryCutoff = batteryCutoff
    }

    private enum CodingKeys: String, CodingKey {
        case app, bootTime, batteryCutoff
    }

    // A record from a build without the cutoff must still be honored, or the guardian would ignore it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(ProcessIdentity.self, forKey: .app)
        bootTime = try container.decode(Int64.self, forKey: .bootTime)
        batteryCutoff =
            try container.decodeIfPresent(Int.self, forKey: .batteryCutoff) ?? BatteryCutoff.standard
    }
}

public struct GuardianObservation: Equatable, Sendable {
    public let armed: ArmedRecord?
    public let sleepDisabled: Bool
    /// The process that holds the armed record's pid right now, if any.
    public let process: ProcessIdentity?
    public let bootTime: Int64
    /// Nil on a Mac without a battery.
    public let battery: BatteryReading?
    /// Debug builds honor the test cutoff; a release guardian clamps it to the normal options.
    public let testMode: Bool

    public init(
        armed: ArmedRecord?, sleepDisabled: Bool, process: ProcessIdentity?, bootTime: Int64,
        battery: BatteryReading? = nil, testMode: Bool = false
    ) {
        self.testMode = testMode
        self.armed = armed
        self.sleepDisabled = sleepDisabled
        self.process = process
        self.bootTime = bootTime
        self.battery = battery
    }
}

/// There is deliberately no effect that turns the mode on.
public enum GuardianEffect: Equatable, Sendable {
    case watchApp(pid: Int32)
    /// Run `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0`; stop here if it fails.
    case revertSleepDisabled
    case recordShutdown(ShutdownReason)
    /// Remove the armed record only if it is still this one, so a newer app instance keeps its own.
    case clearArmed(ArmedRecord)
    case signalApp
}

/// Run at guardian start, when the app's process exits, when the armed record changes and when the power
/// source or the battery level changes.
public func reconcile(_ observation: GuardianObservation) -> [GuardianEffect] {
    guard let armed = observation.armed else { return [] }
    let reason: ShutdownReason
    if observation.process == armed.app {
        let cutoff = BatteryCutoff.normalized(armed.batteryCutoff, testMode: observation.testMode)
        guard observation.battery?.reachesCutoff(cutoff) == true else {
            return [.watchApp(pid: armed.app.pid)]
        }
        reason = .battery
    } else {
        reason = observation.bootTime == armed.bootTime ? .appDied : .reboot
    }
    let revert: [GuardianEffect] = observation.sleepDisabled ? [.revertSleepDisabled] : []
    return revert + [.recordShutdown(reason), .clearArmed(armed), .signalApp]
}
