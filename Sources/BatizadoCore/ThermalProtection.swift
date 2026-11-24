/// How hot the Mac is, in the four steps macOS reports.
public enum ThermalState: String, Codable, Equatable, Sendable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    /// From macOS's `OSThermalPressureLevel`: nominal, moderate, heavy, trapping, sleeping. An unknown higher
    /// level counts as critical, so a new level never keeps the mode on.
    public init(pressureLevel: UInt64) {
        switch pressureLevel {
        case 0: self = .nominal
        case 1: self = .fair
        case 2: self = .serious
        default: self = .critical
        }
    }

    /// The thermal protection turns the mode off here.
    public var isOverheated: Bool {
        switch self {
        case .serious, .critical: true
        case .nominal, .fair: false
        }
    }
}
