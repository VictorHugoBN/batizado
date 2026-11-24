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
    private let guardian: any GuardianLinking
    private let screenLock: any ScreenLocking

    init(
        assertions: any PowerAssertionHolding = SystemPowerAssertions(),
        preferences: any PreferencesStoring = UserDefaultsPreferences(),
        sleepDisabled: any SleepDisabledSensing = SystemSleepDisabledSensor(),
        sleepSwitch: any SleepDisabledSwitching = SudoSleepDisabledSwitch(),
        helperRule: any HelperRuleManaging = SystemHelperRule(),
        guardian: any GuardianLinking = SystemGuardianLink(),
        lid: any LidSensing = SystemLidSensor(),
        displays: any ExternalDisplaySensing = SystemExternalDisplaySensor(),
        screenLock: any ScreenLocking = systemScreenLock()
    ) {
        self.assertions = assertions
        self.preferences = preferences
        self.sleepDisabled = sleepDisabled
        self.sleepSwitch = sleepSwitch
        self.helperRule = helperRule
        self.guardian = guardian
        self.screenLock = screenLock
        state = AppState(preferences: preferences.load())
        send(.launched)
        send(.helperRuleChecked(installed: helperRule.isInstalled()))
        sleepDisabled.start { [weak self] in self?.send(.sleepDisabledChanged($0)) }
        helperRule.watch { [weak self] in self?.send(.helperRuleChecked(installed: $0)) }
        guardian.installAgent()
        guardian.watchShutdowns { [weak self] in self?.send(.shutdownRecorded($0)) }
        displays.start { [weak self] in self?.send(.externalDisplayChanged(active: $0)) }
        lid.start { [weak self] in self?.send(.lidChanged(closed: $0)) }
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
            if ran { send(.sleepDisabledSwitched(disabled)) }
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
        case .arm: send(.armingFinished(succeeded: guardian.arm()))
        case .disarm: guardian.disarm()
        case .lockScreen: _ = screenLock.lock()
        }
    }
}
