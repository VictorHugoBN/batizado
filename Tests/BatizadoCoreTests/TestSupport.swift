@testable import BatizadoCore

func running(keepAwake: Bool = false, keepDisplayOn: Bool = false) -> AppState {
    reduce(AppState(preferences: Preferences(keepAwake: keepAwake, keepDisplayOn: keepDisplayOn)), .launched)
        .state
}

func withRule(_ state: AppState) -> AppState {
    reduce(state, .helperRuleChecked(installed: true)).state
}

func closedLidOn() -> AppState {
    let asked = reduce(withRule(running()), .setClosedLid(true)).state
    return reduce(asked, .sleepDisabledChanged(true)).state
}
