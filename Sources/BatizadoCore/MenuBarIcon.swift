public enum MenuBarIcon: Equatable, Sendable {
    case off
    case awake
    case closedLid
    case diverged
}

extension AppState {
    public var menuBarIcon: MenuBarIcon {
        if closedLidDiverged { return .diverged }
        if sleepDisabled { return .closedLid }
        return keepAwake ? .awake : .off
    }
}
