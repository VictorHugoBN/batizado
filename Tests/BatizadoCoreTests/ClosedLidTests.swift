import Testing

@testable import BatizadoCore

@Test func closedLidDisablesSleepAndTurnsKeepAwakeOn() {
    let (state, effects) = reduce(withRule(running()), .setClosedLid(true))

    #expect(state.keepAwake)
    #expect(effects.contains(.hold(.systemIdle)))
    let armed = reduce(state, .armingFinished(succeeded: true)).state
    #expect(reduce(armed, .acknowledgementFinished(received: true)).effects.contains(.setSleepDisabled(true)))
}

@Test func closedLidWithoutTheRuleAsksToInstallItAndChangesNothingYet() {
    let (state, effects) = reduce(running(), .setClosedLid(true))

    #expect(effects == [.installHelperRule, .requestNotificationPermission])
    #expect(!state.keepAwake)
}

@Test func installingTheRuleFinishesTurningClosedLidOn() {
    let asked = reduce(running(), .setClosedLid(true)).state

    let (state, _) = reduce(asked, .helperRuleInstallFinished(.succeeded))

    #expect(state.helperRule == .installed)
    #expect(state.keepAwake)
    let armed = reduce(state, .armingFinished(succeeded: true)).state
    #expect(reduce(armed, .acknowledgementFinished(received: true)).effects.contains(.setSleepDisabled(true)))
}

@Test func cancellingThePasswordWindowLeavesEverythingOff() {
    let asked = reduce(running(), .setClosedLid(true)).state

    let (state, effects) = reduce(asked, .helperRuleInstallFinished(.cancelled))

    #expect(effects.isEmpty)
    #expect(state.helperRule == .notInstalled)
    #expect(!state.keepAwake)
    #expect(state.closedLidRequest == nil)
}

@Test func aFailedInstallIsShownAndTurnsNothingOn() {
    let asked = reduce(running(), .setClosedLid(true)).state

    let (state, effects) = reduce(asked, .helperRuleInstallFinished(.failed("visudo: syntax error")))

    #expect(effects.isEmpty)
    #expect(state.notice == .installFailed("visudo: syntax error"))
    #expect(!state.keepAwake)
}

@Test func turningKeepAwakeOffTurnsClosedLidOffToo() {
    let closedLid = closedLidOn()

    let (state, effects) = reduce(closedLid, .setKeepAwake(false))

    #expect(!state.keepAwake)
    #expect(state.closedLidRequest == false)
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(effects.contains(.release(.systemIdle)))
}

@Test func turningClosedLidOffKeepsKeepAwakeOn() {
    let (state, effects) = reduce(closedLidOn(), .setClosedLid(false))

    #expect(state.keepAwake)
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(!effects.contains(.release(.systemIdle)))
}

@Test func turningKeepAwakeOffWithoutClosedLidLeavesSleepDisabledAlone() {
    let readZero = reduce(withRule(running(keepAwake: true)), .sleepDisabledChanged(false)).state

    let (_, effects) = reduce(readZero, .setKeepAwake(false))

    #expect(!effects.contains(.setSleepDisabled(false)))
}

@Test func quittingRevertsSleepDisabled() {
    let (_, effects) = reduce(closedLidOn(), .quit)

    #expect(effects.contains(.setSleepDisabled(false)))
}

@Test func quittingWithoutClosedLidDoesNotTouchSleepDisabled() {
    let (_, effects) = reduce(withRule(running(keepAwake: true)), .quit)

    #expect(!effects.contains(.setSleepDisabled(false)))
}

@Test func sleepStillEnabledAfterAskingForClosedLidIsADivergence() {
    let asked = reduce(
        reduce(withRule(running()), .setClosedLid(true)).state, .armingFinished(succeeded: true)
    )
    .state

    let (state, _) = reduce(asked, .sleepDisabledChanged(false))

    #expect(state.closedLidDiverged)
    #expect(state.menuBarIcon == .diverged)
}

@Test func sleepDisabledAsAskedIsNotADivergence() {
    let state = closedLidOn()

    #expect(!state.closedLidDiverged)
    #expect(state.menuBarIcon == .closedLid)
}

@Test func sleepStillDisabledAfterAskingToTurnItOffIsADivergence() {
    let asked = reduce(closedLidOn(), .setClosedLid(false)).state

    let (state, _) = reduce(asked, .sleepDisabledChanged(true))

    #expect(state.closedLidDiverged)
    #expect(state.menuBarIcon == .diverged)
}

@Test func sleepDisabledOutsideTheAppBeforeItAsksIsNotADivergence() {
    let (state, _) = reduce(running(), .sleepDisabledChanged(true))

    #expect(!state.closedLidDiverged)
}

@Test func aRuleRemovedFromOutsideIsReportedAsMissing() {
    let (state, effects) = reduce(withRule(running()), .helperRuleChecked(installed: false))

    #expect(state.helperRule == .missing)
    #expect(effects.isEmpty)
}

@Test func aRuleThatWasNeverInstalledIsNotReportedAsMissing() {
    let (state, _) = reduce(running(), .helperRuleChecked(installed: false))

    #expect(state.helperRule == .notInstalled)
}

@Test func reinstallingAMissingRuleAsksForThePasswordWithoutChangingTheMode() {
    let missing = reduce(closedLidOn(), .helperRuleChecked(installed: false)).state

    let (state, effects) = reduce(missing, .reinstallHelperRule)

    #expect(effects == [.installHelperRule])
    #expect(reduce(state, .helperRuleInstallFinished(.succeeded)).effects.isEmpty)
}

@Test func removingTheRuleTurnsClosedLidOffAndRemovesTheRuleOnlyOnceSleepReadsEnabled() {
    let (state, effects) = reduce(closedLidOn(), .removeHelperRule)
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(!effects.contains(.removeHelperRule))
    #expect(state.closedLidRequest == false)

    #expect(reduce(state, .sleepDisabledChanged(false)).effects.contains(.removeHelperRule))
}

@Test func afterTheRuleIsRemovedClosedLidAsksToInstallAgain() {
    let removing = reduce(withRule(running()), .removeHelperRule).state
    let removed = reduce(removing, .helperRuleRemovalFinished(.succeeded)).state

    let (state, effects) = reduce(removed, .setClosedLid(true))

    #expect(state.helperRule == .notInstalled)
    #expect(effects == [.installHelperRule, .requestNotificationPermission])
}

@Test func cancellingTheRemovalKeepsTheRule() {
    let removing = reduce(withRule(running()), .removeHelperRule).state

    let (state, _) = reduce(removing, .helperRuleRemovalFinished(.cancelled))

    #expect(state.helperRule == .installed)
}

@Test func aFailedRemovalIsShown() {
    let removing = reduce(withRule(running()), .removeHelperRule).state

    let (state, _) = reduce(removing, .helperRuleRemovalFinished(.failed("denied")))

    #expect(state.notice == .removeFailed("denied"))
}

@Test func turningKeepAwakeOffWithAnUnreadableSleepDisabledTurnsClosedLidOffToBeSafe() {
    let unknown = reduce(withRule(running(keepAwake: true)), .sleepDisabledChanged(nil)).state

    #expect(reduce(unknown, .setKeepAwake(false)).effects.contains(.setSleepDisabled(false)))
}

@Test func whenClosedLidCannotBeTurnedOffTheRuleIsKeptAndThePopoverSaysWhy() {
    let removing = reduce(closedLidOn(), .removeHelperRule).state
    let stillOn = reduce(removing, .sleepDisabledChanged(true))
    #expect(!stillOn.effects.contains(.removeHelperRule))

    let (state, effects) = reduce(stillOn.state, .sleepDisabledSettled(true))

    #expect(!effects.contains(.removeHelperRule))
    #expect(state.notice == .ruleKept)
    #expect(!reduce(state, .sleepDisabledChanged(false)).effects.contains(.removeHelperRule))
}

@Test func aLateReadOfZeroAfterTheTurnOffStillRemovesTheRule() {
    let removing = reduce(closedLidOn(), .removeHelperRule).state
    let lagging = reduce(removing, .sleepDisabledChanged(true)).state

    #expect(reduce(lagging, .sleepDisabledSettled(false)).effects.contains(.removeHelperRule))
}

@Test func withClosedLidAlreadyOffTheRuleIsRemovedAtOnce() {
    let off = reduce(withRule(running()), .sleepDisabledChanged(false)).state

    #expect(reduce(off, .removeHelperRule).effects == [.removeHelperRule])
}
