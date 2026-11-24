public enum AppEvent: Equatable, Sendable {
    case launched
    /// Sent once at launch, after the rule, the battery, the heat and any waiting shutdown reason are known.
    case restore
    case setKeepAwake(Bool)
    case setKeepDisplayOn(Bool)
    case setClosedLid(Bool)
    case setLockOnLidClose(Bool)
    case setBatteryCutoff(Int)
    /// Choosing a duration while the mode is on starts it over from now; Never stops the timer.
    case setAutoTurnOff(AutoTurnOff)
    /// The app looked at the clock: at launch, at `nextTimerCheck`, after a wake or a clock change.
    case clockTicked
    /// "Extend 30 min", from the warning notification or the popover.
    case extendTimer
    /// The power source or the battery level changed, or was read at launch; nil without a battery.
    case batteryChanged(BatteryReading?)
    /// The system's thermal state changed, or was read at launch.
    case thermalChanged(ThermalState)
    case helperRuleChecked(installed: Bool)
    case reinstallHelperRule
    case helperRuleInstallFinished(AdministratorOutcome)
    case removeHelperRule
    case helperRuleRemovalFinished(AdministratorOutcome)
    /// The system's `SleepDisabled` was read; nil when the read failed, which is never taken for 0.
    case sleepDisabledChanged(Bool?)
    case armingFinished(succeeded: Bool)
    /// The wait for the guardian ended: a live guardian acknowledged this app's armed record, or none did in
    /// time.
    case acknowledgementFinished(received: Bool)
    /// The guardian process that acknowledged the armed record exited.
    case guardianExited
    /// One of the two allowed `pmset` commands exited cleanly.
    case sleepDisabledSwitched(Bool)
    /// The guardian turned the mode off (or found it off) and left this reason for the app.
    case shutdownRecorded(ShutdownReason)
    /// The built-in display's lid opened or closed, or its state was read at launch.
    case lidChanged(closed: Bool)
    /// At least one display other than the built-in one is active, or none is.
    case externalDisplayChanged(active: Bool)
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
    case arm(batteryCutoff: Int)
    /// Wait up to `GuardianTiming.acknowledgementWait` seconds for a live guardian to acknowledge the armed
    /// record, then report `acknowledgementFinished`; a later wait or a disarm replaces this one.
    case awaitAcknowledgement
    /// Rewrite the armed record with a new cutoff and tell the guardian; Closed lid stays as it is.
    case updateArmed(batteryCutoff: Int)
    /// Remove the armed record and tell the guardian, once `disablesleep` is confirmed off.
    case disarm
    /// Lock the screen now, without sleeping the display or the Mac.
    case lockScreen
    /// Ask once for permission to post notifications; only after the user turns Closed lid on, never at launch.
    case requestNotificationPermission
    /// Tell the user why the mode went off, if notifications are allowed; the popover shows it either way.
    case notify(ShutdownReason)
    /// Post the warning before the timer ends, with the "Extend 30 min" action; never prompts.
    case warnTimer(deadline: Instant)
}

/// `now` is the wall clock when the event happened; the core never reads the clock itself.
public func reduce(_ state: AppState, _ event: AppEvent, at now: Instant) -> (
    state: AppState, effects: [Effect]
) {
    var next = state
    let commands = next.apply(event, at: now)

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
