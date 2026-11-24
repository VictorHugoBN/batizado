import Testing

@testable import BatizadoCore

private let start = Instant(secondsSince1970: 1_000_000)

private func at(_ seconds: Double) -> Instant { start + seconds }

@Test func turningKeepAwakeOnWithADurationSetsTheDeadlineFromNow() {
    let chosen = reduce(running(), .setAutoTurnOff(.twoHours), at: start).state

    let (state, effects) = reduce(chosen, .setKeepAwake(true), at: at(10))

    #expect(state.timerDeadline == at(10 + 2 * 3600))
    #expect(effects.contains(.save(state.preferences)))
}

@Test func choosingADurationWhileOffOnlyRemembersIt() {
    let (state, effects) = reduce(running(), .setAutoTurnOff(.oneHour), at: start)

    #expect(state.autoTurnOff == .oneHour)
    #expect(state.timerDeadline == nil)
    #expect(effects.contains(.save(Preferences(autoTurnOff: .oneHour))))
}

@Test func choosingADurationWhileOnStartsItOverFromNow() {
    let on = reduce(running(keepAwake: true), .setAutoTurnOff(.eightHours), at: start).state

    #expect(reduce(on, .setAutoTurnOff(.oneHour), at: at(60)).state.timerDeadline == at(60 + 3600))
    #expect(reduce(on, .setAutoTurnOff(.never), at: at(60)).state.timerDeadline == nil)
}

@Test func turningOffByHandDropsTheDeadline() {
    let on = reduce(running(keepAwake: true), .setAutoTurnOff(.oneHour), at: start).state

    #expect(reduce(on, .setKeepAwake(false), at: at(5)).state.timerDeadline == nil)
}

@Test func closedLidStartsTheTimerToo() {
    let chosen = reduce(withRule(running()), .setAutoTurnOff(.fourHours), at: start).state

    #expect(reduce(chosen, .setClosedLid(true), at: at(1)).state.timerDeadline == at(1 + 4 * 3600))
}

@Test func onlyDebugBuildsOfferTheTestDuration() {
    #expect(AutoTurnOff.options(testMode: false) == [.never, .oneHour, .twoHours, .fourHours, .eightHours])
    #expect(AutoTurnOff.options(testMode: true).last == .test)
    #expect(AutoTurnOff.normalized(320, testMode: false) == .never)
    #expect(AutoTurnOff.normalized(320, testMode: true) == .test)
    #expect(AutoTurnOff.normalized(1234, testMode: true) == .never)
}

private func oneHourOn() -> AppState {
    reduce(running(keepAwake: true), .setAutoTurnOff(.oneHour), at: start).state
}

@Test func theWarningComesFiveMinutesBeforeTheEndAndOnlyOnce() {
    let early = reduce(oneHourOn(), .clockTicked, at: at(3600 - 301))
    let due = reduce(early.state, .clockTicked, at: at(3600 - 300))
    let again = reduce(due.state, .clockTicked, at: at(3600 - 100))

    #expect(early.effects.isEmpty)
    #expect(due.effects == [.warnTimer(deadline: at(3600))])
    #expect(again.effects.isEmpty)
}

@Test func theAppChecksTheClockAtTheWarningThenAtTheEnd() {
    let on = oneHourOn()
    let warned = reduce(on, .clockTicked, at: at(3600 - 300)).state

    #expect(running().nextTimerCheck == nil)
    #expect(on.nextTimerCheck == at(3600 - 300))
    #expect(warned.nextTimerCheck == at(3600))
}

@Test func theEndTurnsKeepAwakeOffWithTheTimerReasonAndNotifies() {
    let (state, effects) = reduce(oneHourOn(), .clockTicked, at: at(3600))

    #expect(!state.keepAwake)
    #expect(state.lastShutdown == .timer)
    #expect(state.timerDeadline == nil)
    #expect(state.nextTimerCheck == nil)
    #expect(effects.contains(.release(.systemIdle)))
    #expect(effects.contains(.notify(.timer)))
    #expect(!effects.contains(.warnTimer(deadline: at(3600))))
}

@Test func theEndTurnsClosedLidOffToo() {
    let chosen = reduce(closedLidOn(), .setAutoTurnOff(.oneHour), at: start).state

    let (state, effects) = reduce(chosen, .clockTicked, at: at(3601))

    #expect(state.closedLidRequest == false)
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(effects.contains(.notify(.timer)))
}

@Test func extendingAddsThirtyMinutesAndWarnsAgainBeforeTheNewEnd() {
    let warned = reduce(oneHourOn(), .clockTicked, at: at(3600 - 300)).state

    let (state, effects) = reduce(warned, .extendTimer, at: at(3600 - 200))

    #expect(state.timerDeadline == at(3600 + 1800))
    #expect(effects.contains(.save(state.preferences)))
    #expect(state.nextTimerCheck == at(3600 + 1800 - 300))
    #expect(
        reduce(state, .clockTicked, at: at(3600 + 1500)).effects == [.warnTimer(deadline: at(3600 + 1800))])
}

@Test func extendingBeforeTheWarningPushesTheWarningToo() {
    let state = reduce(oneHourOn(), .extendTimer, at: at(60)).state

    #expect(state.timerDeadline == at(3600 + 1800))
    #expect(reduce(state, .clockTicked, at: at(3600)).effects.isEmpty)
}

@Test func extendingAfterTheEndTurnsNothingBackOn() {
    let ended = reduce(oneHourOn(), .clockTicked, at: at(3600)).state

    let (state, effects) = reduce(ended, .extendTimer, at: at(3700))

    #expect(effects.isEmpty)
    #expect(!state.keepAwake)
    #expect(state.timerDeadline == nil)
}

@Test func extendingAPassedDeadlineTheAppHasNotSeenYetEndsItInstead() {
    let (state, effects) = reduce(oneHourOn(), .extendTimer, at: at(4000))

    #expect(!state.keepAwake)
    #expect(state.lastShutdown == .timer)
    #expect(effects.contains(.notify(.timer)))
}

/// How the app starts: preferences from disk, the clock checked, then `launched`.
private func relaunched(_ preferences: Preferences, at now: Instant) -> (state: AppState, effects: [Effect]) {
    let checked = reduce(AppState(preferences: preferences), .clockTicked, at: now)
    let launched = reduce(checked.state, .launched, at: now)
    return (launched.state, checked.effects + launched.effects)
}

@Test func relaunchingBeforeTheEndKeepsTheSameDeadline() {
    let saved = oneHourOn().preferences

    let (state, effects) = relaunched(saved, at: at(1800))

    #expect(state.keepAwake)
    #expect(state.timerDeadline == at(3600))
    #expect(effects.contains(.hold(.systemIdle)))
}

@Test func relaunchingAfterTheEndTurnsOffInsteadOfOn() {
    let saved = oneHourOn().preferences

    let (state, effects) = relaunched(saved, at: at(7200))

    #expect(!state.keepAwake)
    #expect(state.lastShutdown == .timer)
    #expect(!effects.contains(.hold(.systemIdle)))
    #expect(effects.contains(.notify(.timer)))
}

@Test func aCrashIsNotRestoredWhenTheTimerEndedWhileTheAppWasDown() {
    let saved = reduce(closedLidOn(), .setAutoTurnOff(.oneHour), at: start).state.preferences
    let ended = withRule(relaunched(saved, at: at(7200)).state)

    let reported = reduce(ended, .shutdownRecorded(.appDied), at: at(7200))
    let (state, effects) = reduce(reported.state, .restore, at: at(7200))

    #expect(reported.effects.isEmpty)
    #expect(effects.isEmpty)
    #expect(state.lastShutdown == .timer)
}

@Test func aCrashRestoredBeforeTheEndKeepsTheDeadline() {
    let saved = reduce(closedLidOn(), .setAutoTurnOff(.oneHour), at: start).state.preferences
    let back = withRule(relaunched(saved, at: at(600)).state)

    let reported = reduce(back, .shutdownRecorded(.appDied), at: at(600)).state
    let (state, effects) = reduce(reported, .restore, at: at(600))

    #expect(effects.contains(.arm(batteryCutoff: 20)))
    #expect(state.timerDeadline == at(3600))
}

@Test func aProtectionDropsTheDeadline() {
    let chosen = reduce(closedLidOn(), .setAutoTurnOff(.oneHour), at: start).state

    let state = reduce(chosen, .shutdownRecorded(.thermal), at: at(60)).state

    #expect(state.timerDeadline == nil)
    #expect(state.lastShutdown == .thermal)
}

@Test func choosingADurationAsksForNotificationPermissionSoTheWarningCanShow() {
    #expect(
        reduce(running(), .setAutoTurnOff(.twoHours), at: start).effects.last
            == .requestNotificationPermission)
    #expect(
        !reduce(running(), .setAutoTurnOff(.never), at: start).effects.contains(
            .requestNotificationPermission))
}

@Test func relaunchingWithATimerNeverAsksForNotificationPermission() {
    let effects = relaunched(oneHourOn().preferences, at: at(3600 - 60)).effects

    #expect(!effects.contains(.requestNotificationPermission))
    #expect(effects.contains(.warnTimer(deadline: at(3600))))
}
