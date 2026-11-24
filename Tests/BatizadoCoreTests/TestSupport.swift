@testable import BatizadoCore

func running(keepAwake: Bool = false, keepDisplayOn: Bool = false) -> AppState {
    reduce(AppState(preferences: Preferences(keepAwake: keepAwake, keepDisplayOn: keepDisplayOn)), .launched)
        .state
}
