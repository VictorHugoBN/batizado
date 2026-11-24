import Testing

@testable import BatizadoCore

@Test func closedLidArmsTheGuardianAndWaitsForItBeforeDisablingSleep() {
    let (asked, effects) = reduce(withRule(running()), .setClosedLid(true))
    #expect(effects.contains(.arm(batteryCutoff: 20)))
    #expect(!effects.contains(.setSleepDisabled(true)))

    #expect(reduce(asked, .armingFinished(succeeded: true)).effects == [.setSleepDisabled(true)])
}

@Test func installingTheRuleArmsBeforeDisablingSleep() {
    let asked = reduce(running(), .setClosedLid(true)).state

    let (_, effects) = reduce(asked, .helperRuleInstallFinished(.succeeded))

    #expect(effects.contains(.arm(batteryCutoff: 20)))
    #expect(!effects.contains(.setSleepDisabled(true)))
}

@Test func whenArmingFailsSleepIsNeverDisabled() {
    let asked = reduce(withRule(running()), .setClosedLid(true)).state

    let (state, effects) = reduce(asked, .armingFinished(succeeded: false))

    #expect(!effects.contains(.setSleepDisabled(true)))
    #expect(!state.preferences.closedLid)
    #expect(state.notice == .armFailed)
    #expect(!state.closedLidDiverged)
}

@Test func turningClosedLidOffDisarmsOnlyOnceTheCommandSucceeded() {
    let (asked, effects) = reduce(closedLidOn(), .setClosedLid(false))
    #expect(!effects.contains(.disarm))

    #expect(reduce(asked, .sleepDisabledSwitched(false)).effects == [.disarm])
}

@Test func turningClosedLidOffDisarmsWhenSleepIsSeenEnabledAgain() {
    let asked = reduce(closedLidOn(), .setClosedLid(false)).state

    #expect(reduce(asked, .sleepDisabledChanged(false)).effects == [.disarm])
}

@Test func aFailedTurnOffStaysArmed() {
    let asked = reduce(closedLidOn(), .setClosedLid(false)).state

    #expect(reduce(asked, .sleepDisabledChanged(true)).effects.isEmpty)
}

@Test func sleepNotYetDisabledWhileClosedLidIsWantedStaysArmed() {
    let asked = reduce(withRule(running()), .setClosedLid(true)).state

    #expect(reduce(asked, .sleepDisabledChanged(false)).effects.isEmpty)
}

@Test func quittingDisarmsAfterTheRevertSucceeded() {
    let (quitting, effects) = reduce(closedLidOn(), .quit)
    #expect(!effects.contains(.disarm))

    #expect(reduce(quitting, .sleepDisabledSwitched(false)).effects == [.disarm])
}

@Test func disarmingHappensOnce() {
    let asked = reduce(closedLidOn(), .setClosedLid(false)).state
    let disarmed = reduce(asked, .sleepDisabledSwitched(false)).state

    #expect(reduce(disarmed, .sleepDisabledChanged(false)).effects.isEmpty)
}

@Test func turningClosedLidOnTwiceArmsOnce() {
    #expect(!reduce(closedLidOn(), .setClosedLid(true)).effects.contains(.arm(batteryCutoff: 20)))
}

@Test func aCrashRecordedByTheGuardianIsShownAndRestoresClosedLid() {
    let (state, effects) = relaunch(closedLidOn().preferences, reason: .appDied)

    #expect(state.lastShutdown == .appDied)
    #expect(state.keepAwake)
    #expect(effects.contains(.arm(batteryCutoff: 20)))
}

@Test func aRestartRecordedByTheGuardianRestoresClosedLid() {
    #expect(relaunch(closedLidOn().preferences, reason: .reboot).effects.contains(.arm(batteryCutoff: 20)))
}

@Test(arguments: [ShutdownReason.battery, .thermal, .timer])
func aStickyReasonIsShownButNotRestored(reason: ShutdownReason) {
    let (state, effects) = relaunch(closedLidOn().preferences, reason: reason)

    #expect(state.lastShutdown == reason)
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
    #expect(!state.preferences.closedLid)
}

@Test func withoutTheRuleACrashIsShownWithoutAskingForThePassword() {
    let (state, effects) = relaunch(closedLidOn().preferences, rule: false, reason: .appDied)

    #expect(state.lastShutdown == .appDied)
    #expect(state.notice == .notRestored)
    #expect(!effects.contains(.installHelperRule))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func anUnreadableSleepDisabledAfterTurningOffKeepsTheGuardianArmed() {
    let asked = reduce(closedLidOn(), .setClosedLid(false)).state

    #expect(reduce(asked, .sleepDisabledChanged(nil)).effects.isEmpty)
}

@Test func anUnreadableSleepDisabledWhileClosedLidIsWantedIsShownAsAMismatch() {
    #expect(reduce(closedLidOn(), .sleepDisabledChanged(nil)).state.closedLidDiverged)
}
