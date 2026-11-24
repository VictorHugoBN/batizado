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
        static let keepDisplayOn = "keepDisplayOn"
        static let lockOnLidClose = "lockOnLidClose"
        static let batteryCutoff = "batteryCutoff"
    }

    private let defaults = UserDefaults.standard

    func load() -> Preferences {
        Preferences(
            keepAwake: defaults.bool(forKey: Key.keepAwake),
            keepDisplayOn: defaults.bool(forKey: Key.keepDisplayOn),
            lockOnLidClose: defaults.object(forKey: Key.lockOnLidClose) as? Bool ?? true,
            batteryCutoff: BatteryCutoff.normalized(
                defaults.object(forKey: Key.batteryCutoff) as? Int ?? BatteryCutoff.standard,
                testMode: BuildMode.testMode)
        )
    }

    func save(_ preferences: Preferences) {
        defaults.set(preferences.keepAwake, forKey: Key.keepAwake)
        defaults.set(preferences.keepDisplayOn, forKey: Key.keepDisplayOn)
        defaults.set(preferences.lockOnLidClose, forKey: Key.lockOnLidClose)
        defaults.set(preferences.batteryCutoff, forKey: Key.batteryCutoff)
    }
}
