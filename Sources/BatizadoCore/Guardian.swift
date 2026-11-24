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

extension ProcessIdentity {
    /// One copy of the app per user: a copy exits when an older one is running; a tie keeps the lower pid.
    public func yields(to running: [ProcessIdentity]) -> Bool {
        running.contains { other in
            other != self && (other.startedAt, other.pid) < (startedAt, pid)
        }
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

/// A revert the guardian decided on and has not finished; stored so a restart or a cooler reading cannot
/// undo the decision.
public struct PendingRevert: Codable, Equatable, Sendable {
    public let reason: ShutdownReason
    /// The armed record the decision was about, removed once the revert is done.
    public let record: ArmedRecord

    public init(reason: ShutdownReason, record: ArmedRecord) {
        self.reason = reason
        self.record = record
    }
}

public struct GuardianObservation: Equatable, Sendable {
    public let armed: ArmedRecord?
    /// Nil when the system's value could not be read; unknown is never taken for 0.
    public let sleepDisabled: Bool?
    /// The process that holds the armed record's pid right now, if any.
    public let process: ProcessIdentity?
    public let bootTime: Int64
    /// Nil on a Mac without a battery.
    public let battery: BatteryReading?
    /// Nil when the system's thermal state could not be read.
    public let thermal: ThermalState?
    /// Debug builds honor the test cutoff; a release guardian clamps it to the normal options.
    public let testMode: Bool
    /// A revert decided earlier and not finished, by this guardian process or an earlier one.
    public let pending: PendingRevert?

    public init(
        armed: ArmedRecord?, sleepDisabled: Bool?, process: ProcessIdentity?, bootTime: Int64,
        battery: BatteryReading? = nil, thermal: ThermalState? = nil, testMode: Bool = false,
        pending: PendingRevert? = nil
    ) {
        self.pending = pending
        self.testMode = testMode
        self.thermal = thermal
        self.armed = armed
        self.sleepDisabled = sleepDisabled
        self.process = process
        self.bootTime = bootTime
        self.battery = battery
    }
}

/// There is deliberately no effect that turns the mode on.
/// Effects run in order; a failed revert or a note that cannot be written stops the rest and schedules a
/// retry, which only exists while a revert is pending.
public enum GuardianEffect: Equatable, Sendable {
    case watchApp(pid: Int32)
    /// Store the decision before acting on it; a failure to store it does not stop the revert.
    case markPending(PendingRevert)
    /// Run `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0`; stop here if it fails.
    case revertSleepDisabled
    /// Leave the reason for the app; stop here if it cannot be written.
    case recordShutdown(ShutdownReason)
    /// Remove the armed record only if it is still this one, so a newer app instance keeps its own.
    case clearArmed(ArmedRecord)
    case clearPending
    case signalApp
}

/// Run at guardian start, when the app's process exits, when the armed record changes, when the power
/// source or the battery level changes and when the thermal state changes.
public func reconcile(_ observation: GuardianObservation) -> [GuardianEffect] {
    if let pending = observation.pending { return carryOut(pending, observation.sleepDisabled) }
    guard let armed = observation.armed else { return [] }
    let reason: ShutdownReason
    if observation.process == armed.app {
        let cutoff = BatteryCutoff.normalized(armed.batteryCutoff, testMode: observation.testMode)
        if observation.thermal?.isOverheated == true {
            reason = .thermal
        } else if observation.battery?.reachesCutoff(cutoff) == true {
            reason = .battery
        } else {
            return [.watchApp(pid: armed.app.pid)]
        }
    } else {
        reason = observation.bootTime == armed.bootTime ? .appDied : .reboot
    }
    let pending = PendingRevert(reason: reason, record: armed)
    return [.markPending(pending)] + carryOut(pending, observation.sleepDisabled)
}

/// Runs the command unless `SleepDisabled` is confirmed 0; an unknown value is reverted too.
private func carryOut(_ pending: PendingRevert, _ sleepDisabled: Bool?) -> [GuardianEffect] {
    let revert: [GuardianEffect] = sleepDisabled == false ? [] : [.revertSleepDisabled]
    return revert + [.recordShutdown(pending.reason), .clearArmed(pending.record), .clearPending, .signalApp]
}

public enum RevertRetry {
    /// Seconds before the next attempt after `failures` failed ones in a row: 2, 4, 8... at most 60.
    public static func delay(afterFailures failures: Int) -> Int {
        min(60, 1 << min(max(failures, 1), 6))
    }
}
