import Testing

@testable import BatizadoCore

@Test func closingTheLidWithClosedLidOnLocksTheScreen() {
    let open = reduce(closedLidOn(), .lidChanged(closed: false)).state

    let (_, effects) = reduce(open, .lidChanged(closed: true))

    #expect(effects.contains(.lockScreen))
}

@Test func closingTheLidWithClosedLidOffDoesNotLock() {
    let open = reduce(withRule(running(keepAwake: true)), .lidChanged(closed: false)).state

    let (_, effects) = reduce(open, .lidChanged(closed: true))

    #expect(!effects.contains(.lockScreen))
}

@Test func closingTheLidWithLockOnLidCloseOffDoesNotLock() {
    let toggledOff = reduce(closedLidOn(), .setLockOnLidClose(false)).state
    let open = reduce(toggledOff, .lidChanged(closed: false)).state

    let (_, effects) = reduce(open, .lidChanged(closed: true))

    #expect(!effects.contains(.lockScreen))
}

@Test func lockOnLidCloseIsOnByDefaultAndSaved() {
    let (state, effects) = reduce(running(), .setLockOnLidClose(false))

    #expect(AppState().lockOnLidClose)
    #expect(!state.lockOnLidClose)
    #expect(effects.contains(.save(state.preferences)))
}

@Test func closingTheLidWithAnExternalDisplayDoesNotLock() {
    let withDisplay = reduce(closedLidOn(), .externalDisplayChanged(active: true)).state
    let open = reduce(withDisplay, .lidChanged(closed: false)).state

    let (_, effects) = reduce(open, .lidChanged(closed: true))

    #expect(!effects.contains(.lockScreen))
}

@Test func aRepeatedLidClosedReportLocksOnlyOnce() {
    let open = reduce(closedLidOn(), .lidChanged(closed: false)).state
    let closed = reduce(open, .lidChanged(closed: true)).state

    let (_, effects) = reduce(closed, .lidChanged(closed: true))

    #expect(!effects.contains(.lockScreen))
}

@Test func aLidAlreadyClosedWhenFirstReadIsNotAClosing() {
    let (_, effects) = reduce(closedLidOn(), .lidChanged(closed: true))

    #expect(!effects.contains(.lockScreen))
}

@Test func turningClosedLidOnWithTheLidAlreadyClosedDoesNotLock() {
    let closed = reduce(withRule(running()), .lidChanged(closed: true)).state
    let asked = reduce(closed, .setClosedLid(true)).state
    let armed = reduce(asked, .armingFinished(succeeded: true)).state

    let (_, effects) = reduce(armed, .sleepDisabledChanged(true))

    #expect(!effects.contains(.lockScreen))
}

@Test func losingTheLastExternalDisplayWithTheLidClosedLocks() {
    let withDisplay = reduce(closedLidOn(), .externalDisplayChanged(active: true)).state
    let open = reduce(withDisplay, .lidChanged(closed: false)).state
    let closed = reduce(open, .lidChanged(closed: true)).state

    let (_, effects) = reduce(closed, .externalDisplayChanged(active: false))

    #expect(effects.contains(.lockScreen))
}

@Test func losingTheExternalDisplayWithTheLidOpenDoesNotLock() {
    let withDisplay = reduce(closedLidOn(), .externalDisplayChanged(active: true)).state
    let open = reduce(withDisplay, .lidChanged(closed: false)).state

    let (_, effects) = reduce(open, .externalDisplayChanged(active: false))

    #expect(!effects.contains(.lockScreen))
}
