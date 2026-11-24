import BatizadoCore
import BatizadoSystem
import Foundation

@MainActor
protocol PreferencesStoring {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

@MainActor
struct UserDefaultsPreferences: PreferencesStoring {
    private enum Key {
        static let keepAwake = "keepAwake"
        static let closedLid = "closedLid"
        static let keepDisplayOn = "keepDisplayOn"
        static let lockOnLidClose = "lockOnLidClose"
        static let batteryCutoff = "batteryCutoff"
        static let autoTurnOff = "autoTurnOff"
        static let timerDeadline = "timerDeadline"
    }

    private let defaults = UserDefaults.standard

    func load() -> Preferences {
        Preferences(
            keepAwake: defaults.bool(forKey: Key.keepAwake),
            closedLid: defaults.bool(forKey: Key.closedLid),
            keepDisplayOn: defaults.bool(forKey: Key.keepDisplayOn),
            lockOnLidClose: defaults.object(forKey: Key.lockOnLidClose) as? Bool ?? true,
            batteryCutoff: BatteryCutoff.normalized(
                defaults.object(forKey: Key.batteryCutoff) as? Int ?? BatteryCutoff.standard,
                testMode: BuildMode.testMode),
            autoTurnOff: AutoTurnOff.normalized(
                defaults.integer(forKey: Key.autoTurnOff), testMode: BuildMode.testMode),
            timerDeadline: (defaults.object(forKey: Key.timerDeadline) as? Double).map(
                Instant.init(secondsSince1970:))
        )
    }

    func save(_ preferences: Preferences) {
        defaults.set(preferences.keepAwake, forKey: Key.keepAwake)
        defaults.set(preferences.closedLid, forKey: Key.closedLid)
        defaults.set(preferences.keepDisplayOn, forKey: Key.keepDisplayOn)
        defaults.set(preferences.lockOnLidClose, forKey: Key.lockOnLidClose)
        defaults.set(preferences.batteryCutoff, forKey: Key.batteryCutoff)
        defaults.set(preferences.autoTurnOff.rawValue, forKey: Key.autoTurnOff)
        if let deadline = preferences.timerDeadline {
            defaults.set(deadline.secondsSince1970, forKey: Key.timerDeadline)
        } else {
            defaults.removeObject(forKey: Key.timerDeadline)
        }
    }
}
