public enum MenuBarIcon: Equatable, Sendable {
    case off
    case awake
    case closedLid
}

extension AppState {
    public var menuBarIcon: MenuBarIcon {
        if sleepDisabled { return .closedLid }
        return keepAwake ? .awake : .off
    }
}
