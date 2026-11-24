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

/// A new process on saved preferences, in the app's launch order: the clock, the rule, the readings, any
/// reason the guardian left, then the restore.
func relaunch(
    _ saved: Preferences, rule: Bool = true, readings: [AppEvent] = [], reason: ShutdownReason? = nil,
    at now: Instant = Instant(secondsSince1970: 0)
) -> (state: AppState, effects: [Effect]) {
    var events: [AppEvent] = [.clockTicked, .launched, .helperRuleChecked(installed: rule)] + readings
    if let reason { events.append(.shutdownRecorded(reason)) }
    events.append(.restore)
    var state = AppState(preferences: saved)
    var effects: [Effect] = []
    for event in events {
        let step = reduce(state, event, at: now)
        state = step.state
        effects += step.effects
    }
    return (state, effects)
}
