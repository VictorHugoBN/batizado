import Testing

@testable import BatizadoCore

@Test func closedLidIsRestoredAfterQuit() {
    let saved = reduce(closedLidOn(), .quit).state.preferences

    let (state, effects) = relaunch(saved)

    #expect(effects.contains(.arm(batteryCutoff: 20)))
    #expect(state.closedLidRequest == true)
}

@Test(arguments: [ShutdownReason.quit, .appDied, .reboot])
func keepAwakeAndClosedLidComeBackAfterANonStickyShutdown(reason: ShutdownReason) {
    let left = closedLidOn()
    let saved = reason == .quit ? reduce(left, .quit).state.preferences : left.preferences

    let (state, effects) = relaunch(saved, reason: reason == .quit ? nil : reason)

    #expect(state.keepAwake)
    #expect(effects.contains(.hold(.systemIdle)))
    #expect(effects.contains(.arm(batteryCutoff: 20)))
}

@Test func keepAwakeAloneComesBackAfterQuit() {
    let saved = reduce(running(keepAwake: true), .quit).state.preferences

    let (state, effects) = relaunch(saved)

    #expect(state.keepAwake)
    #expect(effects.contains(.hold(.systemIdle)))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test(arguments: [ShutdownReason.battery, .thermal])
func nothingComesBackAfterAProtectionFired(reason: ShutdownReason) {
    let saved = reduce(reduce(closedLidOn(), .shutdownRecorded(reason)).state, .quit).state.preferences

    let (state, effects) = relaunch(saved)

    #expect(!state.keepAwake)
    #expect(!effects.contains(.hold(.systemIdle)))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func nothingComesBackAfterTheTimerEnded() {
    let timed = reduce(closedLidOn(), .setAutoTurnOff(.oneHour)).state
    let ended = reduce(timed, .clockTicked, at: Instant(secondsSince1970: 3600)).state
    let saved = reduce(ended, .quit).state.preferences

    let (state, effects) = relaunch(saved, at: Instant(secondsSince1970: 3700))

    #expect(!state.keepAwake)
    #expect(!effects.contains(.hold(.systemIdle)))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func closedLidTurnedOffByHandStaysOff() {
    let off = reduce(closedLidOn(), .setClosedLid(false)).state
    let saved = reduce(reduce(off, .sleepDisabledSwitched(false)).state, .quit).state.preferences

    let (state, effects) = relaunch(saved, reason: .appDied)

    #expect(state.keepAwake)
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func keepAwakeTurnedOffByHandStaysOffWithClosedLid() {
    let saved = reduce(reduce(closedLidOn(), .setKeepAwake(false)).state, .quit).state.preferences

    let (state, effects) = relaunch(saved)

    #expect(!state.keepAwake)
    #expect(!effects.contains(.hold(.systemIdle)))
    #expect(!effects.contains(.arm(batteryCutoff: 20)))
}

@Test func aRestoreRefusedByTheBatteryIsExplainedAndNotTriedAgainLater() {
    let low = [AppEvent.batteryChanged(BatteryReading(onAC: false, percent: 10))]
    let refused = relaunch(closedLidOn().preferences, readings: low)
    #expect(refused.state.notice == .batteryLow(percent: 10, cutoff: 20))

    let charged = [AppEvent.batteryChanged(BatteryReading(onAC: true, percent: 90))]
    #expect(!relaunch(refused.state.preferences, readings: charged).effects.contains(.arm(batteryCutoff: 20)))
}

@Test func aRestoreWithoutTheRuleIsExplainedOnceAndNeverAsksForThePassword() {
    let missing = relaunch(closedLidOn().preferences, rule: false)
    #expect(missing.state.notice == .notRestored)
    #expect(!missing.effects.contains(.installHelperRule))

    let next = relaunch(missing.state.preferences, rule: false)
    #expect(next.state.notice == nil)
}

@Test func aCrashReportArrivingAfterTheRestorePutsClosedLidBackOn() {
    let restored = relaunch(closedLidOn().preferences).state
    let armed = reduce(reduce(restored, .armingFinished(succeeded: true)).state, .sleepDisabledChanged(true))
    let reverted = reduce(armed.state, .sleepDisabledChanged(false)).state

    let (state, effects) = reduce(reverted, .shutdownRecorded(.reboot))

    #expect(effects.contains(.setSleepDisabled(true)))
    #expect(state.lastShutdown == .reboot)
}

@Test func aCrashReportWithoutAnIntentionTurnsNothingOn() {
    let restored = relaunch(running(keepAwake: true).preferences).state

    #expect(reduce(restored, .shutdownRecorded(.appDied)).effects.isEmpty)
}
