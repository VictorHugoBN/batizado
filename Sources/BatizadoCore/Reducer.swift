public enum AppEvent: Equatable, Sendable {
    case launched
    case setKeepAwake(Bool)
    case setKeepDisplayOn(Bool)
    case quit
}

public enum Effect: Hashable, Sendable {
    case hold(PowerAssertion)
    case release(PowerAssertion)
    case save(Preferences)
}

public func reduce(_ state: AppState, _ event: AppEvent) -> (state: AppState, effects: [Effect]) {
    var next = state
    next.apply(event)

    var effects = PowerAssertion.allCases.compactMap { assertion -> Effect? in
        switch (state.assertions.contains(assertion), next.assertions.contains(assertion)) {
        case (false, true): .hold(assertion)
        case (true, false): .release(assertion)
        default: nil
        }
    }
    if next.preferences != state.preferences {
        effects.append(.save(next.preferences))
    }
    return (next, effects)
}
