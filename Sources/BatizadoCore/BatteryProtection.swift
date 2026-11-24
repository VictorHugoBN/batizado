/// The power source feeding the Mac and the internal battery's charge.
public struct BatteryReading: Codable, Equatable, Sendable {
    public let onAC: Bool
    public let percent: Int

    public init(onAC: Bool, percent: Int) {
        self.onAC = onAC
        self.percent = percent
    }

    /// The low battery protection turns the mode off here; it never fires on the charger.
    public func reachesCutoff(_ cutoff: Int) -> Bool {
        !onAC && percent <= cutoff
    }
}

/// The battery percentage at or below which the protection turns the mode off.
public enum BatteryCutoff {
    public static let standard = 20
    /// Only debug builds offer it, so a full battery can trip the protection when the charger is unplugged.
    public static let testValue = 100
    private static let range = 5...50
    private static let step = 5

    public static func options(testMode: Bool) -> [Int] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
            + (testMode ? [testValue] : [])
    }

    /// A stored value outside the options (an old preference, a hand-edited record) becomes a valid one.
    public static func normalized(_ value: Int, testMode: Bool) -> Int {
        if testMode, value == testValue { return value }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return clamped - clamped % step
    }
}
