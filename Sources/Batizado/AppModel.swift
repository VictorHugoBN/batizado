import BatizadoCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState

    private let assertions: any PowerAssertionHolding
    private let preferences: any PreferencesStoring
    private let sleepDisabled: any SleepDisabledSensing

    init(
        assertions: any PowerAssertionHolding = SystemPowerAssertions(),
        preferences: any PreferencesStoring = UserDefaultsPreferences(),
        sleepDisabled: any SleepDisabledSensing = SystemSleepDisabledSensor()
    ) {
        self.assertions = assertions
        self.preferences = preferences
        self.sleepDisabled = sleepDisabled
        state = AppState(preferences: preferences.load())
        send(.launched)
        sleepDisabled.start { [weak self] in self?.send(.sleepDisabledChanged($0)) }
    }

    func send(_ event: AppEvent) {
        let (next, effects) = reduce(state, event)
        state = next
        effects.forEach(run)
    }

    private func run(_ effect: Effect) {
        switch effect {
        case .hold(let assertion): assertions.hold(assertion)
        case .release(let assertion): assertions.release(assertion)
        case .save(let toggles): preferences.save(toggles)
        }
    }
}
