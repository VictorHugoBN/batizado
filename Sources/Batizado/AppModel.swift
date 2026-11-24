import BatizadoCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState

    private let assertions: any PowerAssertionHolding
    private let preferences: any PreferencesStoring
    private let sleepDisabled: any SleepDisabledSensing
    private let sleepSwitch: any SleepDisabledSwitching
    private let helperRule: any HelperRuleManaging

    init(
        assertions: any PowerAssertionHolding = SystemPowerAssertions(),
        preferences: any PreferencesStoring = UserDefaultsPreferences(),
        sleepDisabled: any SleepDisabledSensing = SystemSleepDisabledSensor(),
        sleepSwitch: any SleepDisabledSwitching = SudoSleepDisabledSwitch(),
        helperRule: any HelperRuleManaging = SystemHelperRule()
    ) {
        self.assertions = assertions
        self.preferences = preferences
        self.sleepDisabled = sleepDisabled
        self.sleepSwitch = sleepSwitch
        self.helperRule = helperRule
        state = AppState(preferences: preferences.load())
        send(.launched)
        send(.helperRuleChecked(installed: helperRule.isInstalled()))
        sleepDisabled.start { [weak self] in self?.send(.sleepDisabledChanged($0)) }
        helperRule.watch { [weak self] in self?.send(.helperRuleChecked(installed: $0)) }
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
        case .setSleepDisabled(let disabled):
            let ran = sleepSwitch.set(disabled)
            // Read back at once: the change notification is not guaranteed to arrive.
            send(.sleepDisabledChanged(sleepDisabled.current()))
            if !ran { send(.helperRuleChecked(installed: helperRule.isInstalled())) }
            // powerd may apply the setting a moment after pmset exits; one late read clears a false warning.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.send(.sleepDisabledChanged(self.sleepDisabled.current()))
            }
        case .installHelperRule: send(.helperRuleInstallFinished(helperRule.install()))
        case .removeHelperRule: send(.helperRuleRemovalFinished(helperRule.remove()))
        }
    }
}
