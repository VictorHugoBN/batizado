import Testing

@testable import BatizadoCore

@Test func iconIsOffWhenNothingKeepsTheMacAwake() {
    #expect(running().menuBarIcon == .off)
}

@Test func iconIsAwakeWhileKeepAwakeIsOnAndSleepIsStillAllowed() {
    #expect(running(keepAwake: true).menuBarIcon == .awake)
}

@Test func iconShowsClosedLidWhenTheSystemReportsSleepDisabled() {
    let (state, effects) = reduce(running(keepAwake: true), .sleepDisabledChanged(true))

    #expect(state.sleepDisabled)
    #expect(state.menuBarIcon == .closedLid)
    #expect(effects.isEmpty)
}

@Test func iconFollowsTheSystemBackWhenSleepIsAllowedAgain() {
    let closedLid = reduce(running(keepAwake: true), .sleepDisabledChanged(true)).state

    let (state, _) = reduce(closedLid, .sleepDisabledChanged(false))

    #expect(!state.sleepDisabled)
    #expect(state.menuBarIcon == .awake)
}

@Test func iconShowsClosedLidWhenSleepIsDisabledOutsideTheApp() {
    let (state, effects) = reduce(running(), .sleepDisabledChanged(true))

    #expect(state.menuBarIcon == .closedLid)
    #expect(!state.keepAwake)
    #expect(effects.isEmpty)
}
