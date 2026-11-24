@testable import BatizadoCore

/// Tests that do not care about the clock run at a fixed instant.
func reduce(_ state: AppState, _ event: AppEvent) -> (state: AppState, effects: [Effect]) {
    reduce(state, event, at: Instant(secondsSince1970: 0))
}

func running(keepAwake: Bool = false, keepDisplayOn: Bool = false) -> AppState {
    reduce(AppState(preferences: Preferences(keepAwake: keepAwake, keepDisplayOn: keepDisplayOn)), .launched)
        .state
}

func withRule(_ state: AppState) -> AppState {
    reduce(state, .helperRuleChecked(installed: true)).state
}

func closedLidOn() -> AppState {
    let asked = reduce(withRule(running()), .setClosedLid(true)).state
    let armed = reduce(asked, .armingFinished(succeeded: true)).state
    return reduce(armed, .sleepDisabledChanged(true)).state
}
