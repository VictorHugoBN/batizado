import Testing

@testable import BatizadoCore

private func waitingForTheGuardian() -> AppState {
    let readZero = reduce(withRule(running()), .sleepDisabledChanged(false)).state
    return reduce(reduce(readZero, .setClosedLid(true)).state, .armingFinished(succeeded: true)).state
}

@Test func withoutAnAcknowledgementInTimeClosedLidStaysOffAndTheRecordIsRemoved() {
    let (state, effects) = reduce(waitingForTheGuardian(), .acknowledgementFinished(received: false))

    #expect(effects.contains(.disarm))
    #expect(!effects.contains(.setSleepDisabled(true)))
    #expect(state.notice == .guardianNotRunning)
    #expect(!state.preferences.closedLid)
    #expect(!state.awaitingGuardian)
    #expect(!state.closedLidDiverged)
}

@Test func aGuardianThatExitsWhileClosedLidIsOnIsWaitedForAgain() {
    let (lost, effects) = reduce(closedLidOn(), .guardianExited)
    #expect(effects == [.awaitAcknowledgement])

    #expect(reduce(lost, .acknowledgementFinished(received: true)).effects.isEmpty)
}

@Test func aGuardianThatDoesNotComeBackTurnsClosedLidOffAndDisarmsOnceItIsOff() {
    let lost = reduce(closedLidOn(), .guardianExited).state

    let (off, effects) = reduce(lost, .acknowledgementFinished(received: false))
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(!effects.contains(.disarm))
    #expect(off.notice == .guardianLost)
    #expect(!off.preferences.closedLid)

    #expect(reduce(off, .sleepDisabledSwitched(false)).effects == [.disarm])
}

@Test func anAcknowledgementArrivingAfterClosedLidWasTurnedOffTurnsNothingOn() {
    let asked = reduce(waitingForTheGuardian(), .setClosedLid(false)).state
    let off = reduce(asked, .sleepDisabledSwitched(false)).state

    #expect(reduce(off, .acknowledgementFinished(received: true)).effects.isEmpty)
}

@Test func aGuardianExitIsIgnoredWhileNothingIsArmed() {
    #expect(reduce(withRule(running()), .guardianExited).effects.isEmpty)
}

@Test func turningClosedLidOnAgainWhileWaitingStartsNoSecondWait() {
    let effects = reduce(waitingForTheGuardian(), .setClosedLid(true)).effects

    #expect(!effects.contains(.awaitAcknowledgement))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func theLaunchRestoreAlsoWaitsForTheGuardian() {
    let restoring = relaunch(closedLidOn().preferences).state
    let armed = reduce(restoring, .armingFinished(succeeded: true))
    #expect(armed.effects == [.awaitAcknowledgement])

    let (state, effects) = reduce(armed.state, .acknowledgementFinished(received: false))
    #expect(!effects.contains(.setSleepDisabled(true)))
    #expect(state.notice == .guardianNotRunning)
    #expect(!state.preferences.closedLid)
}

@Test func anUnreadableSleepDisabledWhenTheWaitEndsIsTurnedOffBeforeDisarming() {
    let unknown = reduce(waitingForTheGuardian(), .sleepDisabledChanged(nil)).state

    let effects = reduce(unknown, .acknowledgementFinished(received: false)).effects

    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(!effects.contains(.disarm))
}
