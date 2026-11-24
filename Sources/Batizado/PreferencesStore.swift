import BatizadoCore
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
    }

    private let defaults = UserDefaults.standard

    func load() -> Preferences {
        Preferences(
            keepAwake: defaults.bool(forKey: Key.keepAwake),
            keepDisplayOn: defaults.bool(forKey: Key.keepDisplayOn)
        )
    }

    func save(_ preferences: Preferences) {
        defaults.set(preferences.keepAwake, forKey: Key.keepAwake)
        defaults.set(preferences.keepDisplayOn, forKey: Key.keepDisplayOn)
    }
}
