public enum AppEvent: Equatable, Sendable {
    case launched
    case setKeepAwake(Bool)
    case setKeepDisplayOn(Bool)
    case setClosedLid(Bool)
    case helperRuleChecked(installed: Bool)
    case reinstallHelperRule
    case helperRuleInstallFinished(AdministratorOutcome)
    case removeHelperRule
    case helperRuleRemovalFinished(AdministratorOutcome)
    case sleepDisabledChanged(Bool)
    case armingFinished(succeeded: Bool)
    /// One of the two allowed `pmset` commands exited cleanly.
    case sleepDisabledSwitched(Bool)
    /// The guardian turned the mode off (or found it off) and left this reason for the app.
    case shutdownRecorded(ShutdownReason)
    case quit
}

public enum Effect: Hashable, Sendable {
    case hold(PowerAssertion)
    case release(PowerAssertion)
    case save(Preferences)
    /// Run `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0|1`, then report the value read back.
    case setSleepDisabled(Bool)
    /// Explain what will be installed, then install `HelperRule` through the administrator password window.
    case installHelperRule
    /// Remove `HelperRule.path` through the administrator password window.
    case removeHelperRule
    /// Write the armed record and tell the guardian, then report `armingFinished`; nothing goes on before.
    case arm
    /// Remove the armed record and tell the guardian, once `disablesleep` is confirmed off.
    case disarm
}

public func reduce(_ state: AppState, _ event: AppEvent) -> (state: AppState, effects: [Effect]) {
    var next = state
    let commands = next.apply(event)

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
    return (next, effects + commands)
}
