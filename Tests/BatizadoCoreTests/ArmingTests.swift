import Testing

@testable import BatizadoCore

@Test func closedLidArmsTheGuardianAndWaitsForItBeforeDisablingSleep() {
    let (asked, effects) = reduce(withRule(running()), .setClosedLid(true))
    #expect(effects.contains(.arm))
    #expect(!effects.contains(.setSleepDisabled(true)))

    #expect(reduce(asked, .armingFinished(succeeded: true)).effects == [.setSleepDisabled(true)])
}

@Test func installingTheRuleArmsBeforeDisablingSleep() {
    let asked = reduce(running(), .setClosedLid(true)).state

    let (_, effects) = reduce(asked, .helperRuleInstallFinished(.succeeded))

    #expect(effects.contains(.arm))
    #expect(!effects.contains(.setSleepDisabled(true)))
}

@Test func whenArmingFailsSleepIsNeverDisabled() {
    let asked = reduce(withRule(running()), .setClosedLid(true)).state

    let (state, effects) = reduce(asked, .armingFinished(succeeded: false))

    #expect(effects.isEmpty)
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
    #expect(!reduce(closedLidOn(), .setClosedLid(true)).effects.contains(.arm))
}

@Test func aCrashRecordedByTheGuardianIsShownAndRestoresClosedLid() {
    let (state, effects) = reduce(withRule(running()), .shutdownRecorded(.appDied))

    #expect(state.lastShutdown == .appDied)
    #expect(state.keepAwake)
    #expect(effects.contains(.arm))
}

@Test func aRestartRecordedByTheGuardianRestoresClosedLid() {
    #expect(reduce(withRule(running()), .shutdownRecorded(.reboot)).effects.contains(.arm))
}

@Test(arguments: [ShutdownReason.battery, .thermal, .timer])
func aStickyReasonIsShownButNotRestored(reason: ShutdownReason) {
    let (state, effects) = reduce(withRule(running()), .shutdownRecorded(reason))

    #expect(state.lastShutdown == reason)
    #expect(!effects.contains(.arm))
}

@Test func withoutTheRuleACrashIsShownWithoutAskingForThePassword() {
    let (state, effects) = reduce(running(), .shutdownRecorded(.appDied))

    #expect(state.lastShutdown == .appDied)
    #expect(effects.isEmpty)
}
