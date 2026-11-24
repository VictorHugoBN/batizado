import BatizadoCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState

    private let assertions: any PowerAssertionHolding
    private let preferences: any PreferencesStoring

    init(
        assertions: any PowerAssertionHolding = SystemPowerAssertions(),
        preferences: any PreferencesStoring = UserDefaultsPreferences()
    ) {
        self.assertions = assertions
        self.preferences = preferences
        state = AppState(preferences: preferences.load())
        send(.launched)
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
