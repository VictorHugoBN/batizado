import Testing

@testable import BatizadoCore

@Test(arguments: [(15, true), (20, true), (21, false), (80, false)])
func onBatteryTheProtectionFiresAtOrBelowTheCutoff(percent: Int, fires: Bool) {
    #expect(BatteryReading(onAC: false, percent: percent).reachesCutoff(20) == fires)
}

@Test(arguments: [1, 5, 20, 50])
func onTheChargerTheProtectionNeverFires(percent: Int) {
    #expect(!BatteryReading(onAC: true, percent: percent).reachesCutoff(50))
}

@Test func theCutoffDefaultsTo20AndGoesFrom5To50InStepsOf5() {
    #expect(BatteryCutoff.standard == 20)
    #expect(BatteryCutoff.options(testMode: false) == [5, 10, 15, 20, 25, 30, 35, 40, 45, 50])
}

@Test func onlyTheTestModeOffersACutoffAboveAFullBattery() {
    #expect(BatteryCutoff.options(testMode: true).last == 100)
    #expect(BatteryCutoff.normalized(100, testMode: true) == 100)
    #expect(BatteryCutoff.normalized(100, testMode: false) == 50)
}

@Test(arguments: [(0, 5), (23, 20), (50, 50), (75, 50)])
func anInvalidCutoffFallsBackToAValidOption(stored: Int, used: Int) {
    #expect(BatteryCutoff.normalized(stored, testMode: false) == used)
}

private func onBattery(_ percent: Int, _ state: AppState) -> AppState {
    reduce(state, .batteryChanged(BatteryReading(onAC: false, percent: percent))).state
}

@Test func closedLidIsRefusedWithAnExplanationWhenTheProtectionWouldFireAtOnce() {
    let (state, effects) = reduce(onBattery(15, withRule(running())), .setClosedLid(true))

    #expect(effects.isEmpty)
    #expect(state.notice == .batteryLow(percent: 15, cutoff: 20))
    #expect(!state.keepAwake)
    #expect(!state.closedLidDiverged)
}

@Test func theRefusalComesBeforeAskingForThePassword() {
    let (state, effects) = reduce(onBattery(20, running()), .setClosedLid(true))

    #expect(effects.isEmpty)
    #expect(state.notice == .batteryLow(percent: 20, cutoff: 20))
}

@Test func aLowBatteryOnTheChargerDoesNotRefuseClosedLid() {
    let charging = reduce(withRule(running()), .batteryChanged(BatteryReading(onAC: true, percent: 5))).state

    #expect(reduce(charging, .setClosedLid(true)).effects.contains(.arm(batteryCutoff: 20)))
}

@Test func aCrashIsNotRestoredWhenTheBatteryIsAlreadyAtTheCutoff() {
    let (state, effects) = reduce(onBattery(10, withRule(running())), .shutdownRecorded(.appDied))

    #expect(!effects.contains(.arm(batteryCutoff: 20)))
    #expect(state.notice == .batteryLow(percent: 10, cutoff: 20))
}

@Test func theBatteryProtectionTurnsOffClosedLidAndKeepAwakeAndNotifies() {
    let (state, effects) = reduce(closedLidOn(), .shutdownRecorded(.battery))

    #expect(state.lastShutdown == .battery)
    #expect(!state.keepAwake)
    #expect(state.closedLidRequest == false)
    #expect(effects.contains(.release(.systemIdle)))
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(effects.contains(.notify(.battery)))
}

@Test func pluggingTheChargerBackInTurnsNothingOn() {
    let reverted = reduce(closedLidOn(), .shutdownRecorded(.battery)).state

    let (state, effects) = reduce(
        reverted, .batteryChanged(BatteryReading(onAC: true, percent: 19)))

    #expect(effects.isEmpty)
    #expect(!state.keepAwake)
    #expect(state.lastShutdown == .battery)
}

@Test func aCrashRestoredOnLaunchIsNotNotified() {
    #expect(!reduce(withRule(running()), .shutdownRecorded(.appDied)).effects.contains(.notify(.appDied)))
}

@Test func theCutoffIsSavedAndArmedWithClosedLid() {
    let (changed, effects) = reduce(withRule(running()), .setBatteryCutoff(35))

    #expect(effects == [.save(Preferences(batteryCutoff: 35))])
    #expect(reduce(changed, .setClosedLid(true)).effects.contains(.arm(batteryCutoff: 35)))
}

@Test func changingTheCutoffWhileArmedKeepsTheGuardianCurrent() {
    #expect(reduce(closedLidOn(), .setBatteryCutoff(30)).effects.contains(.updateArmed(batteryCutoff: 30)))
}

@Test func theUsersFirstClosedLidAsksForNotificationPermission() {
    #expect(reduce(withRule(running()), .setClosedLid(true)).effects.last == .requestNotificationPermission)
    #expect(reduce(running(), .setClosedLid(true)).effects.last == .requestNotificationPermission)
}

@Test func neitherALaunchRestoreNorARefusalAsksForNotificationPermission() {
    let restore = reduce(withRule(running()), .shutdownRecorded(.reboot)).effects
    let refusal = reduce(onBattery(5, withRule(running())), .setClosedLid(true)).effects

    #expect(!restore.contains(.requestNotificationPermission))
    #expect(!refusal.contains(.requestNotificationPermission))
}
