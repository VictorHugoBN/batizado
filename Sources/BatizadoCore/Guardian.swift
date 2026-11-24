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
    /// New each time the app arms, so an acknowledgement of an earlier, identical record never counts.
    public let id: String

    public init(app: ProcessIdentity, bootTime: Int64, batteryCutoff: Int, id: String = "") {
        self.app = app
        self.bootTime = bootTime
        self.batteryCutoff = batteryCutoff
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case app, bootTime, batteryCutoff, id
    }

    // A record from a build without the cutoff must still be honored, or the guardian would ignore it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(ProcessIdentity.self, forKey: .app)
        bootTime = try container.decode(Int64.self, forKey: .bootTime)
        batteryCutoff =
            try container.decodeIfPresent(Int.self, forKey: .batteryCutoff) ?? BatteryCutoff.standard
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    }
}

/// Written by a guardian that took charge of an armed record; the app turns `disablesleep` on only after one.
public struct Acknowledgement: Codable, Equatable, Sendable {
    public let record: ArmedRecord
    /// The guardian process that wrote it.
    public let guardian: ProcessIdentity

    public init(record: ArmedRecord, guardian: ProcessIdentity) {
        self.record = record
        self.guardian = guardian
    }
}

extension Acknowledgement {
    /// True only for this exact record, from a guardian that is still the same running process; an
    /// acknowledgement left by a guardian that exited, or for an earlier record, never counts.
    public func confirms(_ current: ArmedRecord, guardianNow: ProcessIdentity?) -> Bool {
        record == current && guardianNow == guardian
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
    /// This guardian process; nil when it cannot be read, and then it acknowledges nothing.
    public let guardian: ProcessIdentity?
    /// The acknowledgement on disk, from this guardian or an earlier one.
    public let acknowledged: Acknowledgement?

    public init(
        armed: ArmedRecord?, sleepDisabled: Bool?, process: ProcessIdentity?, bootTime: Int64,
        battery: BatteryReading? = nil, thermal: ThermalState? = nil, testMode: Bool = false,
        pending: PendingRevert? = nil, guardian: ProcessIdentity? = nil,
        acknowledged: Acknowledgement? = nil
    ) {
        self.pending = pending
        self.guardian = guardian
        self.acknowledged = acknowledged
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
    /// Write the acknowledgement and tell the app.
    case acknowledge(Acknowledgement)
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
    /// Call `recheck(afterClearing:)` once, `GuardianTiming.recheckGrace` seconds from now.
    case recheckAfterGrace(ArmedRecord)
}

public enum GuardianTiming {
    /// How long after clearing a dead app's record a `disablesleep 1` it launched may still land.
    public static let recheckGrace = 5
    /// How long the app waits for a guardian to acknowledge its record: when it arms, and when the guardian
    /// exits and launchd should bring it back (an early exit is restarted after up to 10 s).
    public static let acknowledgementWait = 12
}

/// Run at guardian start, when the app's process exits, when the armed record changes, when the power
/// source or the battery level changes and when the thermal state changes.
public func reconcile(_ observation: GuardianObservation) -> [GuardianEffect] {
    if let pending = observation.pending {
        return carryOut(pending, observation.sleepDisabled) + recheck(pending, observation.sleepDisabled)
    }
    guard let armed = observation.armed else { return [] }
    let reason: ShutdownReason
    if observation.process == armed.app {
        let cutoff = BatteryCutoff.normalized(armed.batteryCutoff, testMode: observation.testMode)
        if observation.thermal?.isOverheated == true {
            reason = .thermal
        } else if observation.battery?.reachesCutoff(cutoff) == true {
            reason = .battery
        } else {
            return [.watchApp(pid: armed.app.pid)] + acknowledge(armed, observation)
        }
    } else {
        reason = observation.bootTime == armed.bootTime ? .appDied : .reboot
    }
    let pending = PendingRevert(reason: reason, record: armed)
    return [.markPending(pending)] + carryOut(pending, observation.sleepDisabled)
        + recheck(pending, observation.sleepDisabled)
}

/// An app that died right after launching `disablesleep 1` leaves it to land after its record is gone.
private func recheck(_ pending: PendingRevert, _ sleepDisabled: Bool?) -> [GuardianEffect] {
    pending.reason == .appDied && sleepDisabled != true ? [.recheckAfterGrace(pending.record)] : []
}

/// Written once per record and guardian process, not again on every battery change.
private func acknowledge(_ armed: ArmedRecord, _ observation: GuardianObservation) -> [GuardianEffect] {
    guard let guardian = observation.guardian else { return [] }
    let acknowledgement = Acknowledgement(record: armed, guardian: guardian)
    return observation.acknowledged == acknowledgement ? [] : [.acknowledge(acknowledgement)]
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

/// Run once, `GuardianTiming.recheckGrace` after the record of a dead app was cleared with `SleepDisabled`
/// read 0 or unknown. The mode showing up since, with no newer armed record, is that app's last command.
public func recheck(afterClearing record: ArmedRecord, _ observation: GuardianObservation)
    -> [GuardianEffect]
{
    guard observation.pending == nil, observation.armed == nil, observation.sleepDisabled != false else {
        return []
    }
    let pending = PendingRevert(reason: .appDied, record: record)
    return [.markPending(pending)] + carryOut(pending, observation.sleepDisabled)
}
