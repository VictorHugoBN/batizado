/// A wall-clock instant; the app reads the clock and hands it to the core, which never reads it itself.
public struct Instant: Comparable, Hashable, Sendable {
    public let secondsSince1970: Double

    public init(secondsSince1970: Double) {
        self.secondsSince1970 = secondsSince1970
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool {
        lhs.secondsSince1970 < rhs.secondsSince1970
    }

    public static func + (instant: Instant, seconds: Double) -> Instant {
        Instant(secondsSince1970: instant.secondsSince1970 + seconds)
    }

    public static func - (instant: Instant, seconds: Double) -> Instant {
        instant + -seconds
    }
}

/// How long the mode stays on before the timer turns everything off; the raw value is in seconds.
public enum AutoTurnOff: Int, CaseIterable, Sendable {
    case never = 0
    case oneHour = 3600
    case twoHours = 7200
    case fourHours = 14400
    case eightHours = 28800
    /// Debug builds only: the warning comes 20 seconds in, the end 5 minutes later.
    case test = 320

    public static let warningLead: Double = 5 * 60
    public static let extensionLength: Double = 30 * 60

    public static func options(testMode: Bool) -> [AutoTurnOff] {
        allCases.filter { testMode || $0 != .test }
    }

    /// A stored value that is not an option (an old preference, the test value in a release build) is Never.
    public static func normalized(_ seconds: Int, testMode: Bool) -> AutoTurnOff {
        guard let value = AutoTurnOff(rawValue: seconds), options(testMode: testMode).contains(value) else {
            return .never
        }
        return value
    }

    func deadline(from now: Instant) -> Instant? {
        self == .never ? nil : now + Double(rawValue)
    }
}
