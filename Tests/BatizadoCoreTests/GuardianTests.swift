import Testing

@testable import BatizadoCore

private let app = ProcessIdentity(pid: 4242, startedAt: 1_700_000_000_123_456)
private let boot: Int64 = 1_699_990_000
private let armed = ArmedRecord(app: app, bootTime: boot, batteryCutoff: 20)

private func observe(
    armed record: ArmedRecord? = armed,
    sleepDisabled: Bool? = true,
    running: ProcessIdentity? = app,
    bootTime: Int64 = boot,
    battery: BatteryReading? = nil,
    thermal: ThermalState? = nil,
    testMode: Bool = false,
    pending: PendingRevert? = nil
) -> [GuardianEffect] {
    reconcile(
        GuardianObservation(
            armed: record, sleepDisabled: sleepDisabled, process: running, bootTime: bootTime,
            battery: battery,
            thermal: thermal,
            testMode: testMode,
            pending: pending)
    )
}

/// A decision taken now: stored first, then carried out.
private func decided(_ reason: ShutdownReason, runs: Bool = true) -> [GuardianEffect] {
    [.markPending(PendingRevert(reason: reason, record: armed))] + carriedOut(reason, runs: runs)
}

private func carriedOut(_ reason: ShutdownReason, runs: Bool = true) -> [GuardianEffect] {
    (runs ? [.revertSleepDisabled] : [])
        + [.recordShutdown(reason), .clearArmed(armed), .clearPending, .signalApp]
}

@Test func armedWithTheAppAliveOnlyWatchesIt() {
    #expect(observe() == [.watchApp(pid: 4242)])
}

@Test func armedWithTheAppDeadRevertsAndRecordsAppDied() {
    #expect(observe(running: nil) == decided(.appDied))
}

@Test func aRecycledPidIsNotMistakenForTheApp() {
    let stranger = ProcessIdentity(pid: 4242, startedAt: 1_700_000_999_000_000)

    #expect(observe(running: stranger).contains(.revertSleepDisabled))
}

@Test func armedBeforeARestartRecordsReboot() {
    #expect(observe(running: nil, bootTime: boot + 86_400).contains(.recordShutdown(.reboot)))
}

@Test func nothingArmedNeverTouchesSleepDisabledSetOutsideTheApp() {
    #expect(observe(armed: nil, sleepDisabled: true, running: nil).isEmpty)
}

@Test func aStaleRecordWithSleepAlreadyEnabledIsClearedAndReportedWithoutRunningAnything() {
    #expect(
        observe(sleepDisabled: false, running: nil)
            == decided(.appDied, runs: false) + [.recheckAfterGrace(armed)])
}

@Test(arguments: [ShutdownReason.battery, .thermal, .timer])
func protectionsAndTheTimerAreSticky(reason: ShutdownReason) {
    #expect(reason.isSticky)
}

@Test(arguments: [ShutdownReason.user, .quit, .appDied, .reboot])
func crashesRestartsAndTheUserAreNotSticky(reason: ShutdownReason) {
    #expect(!reason.isSticky)
}

@Test func onBatteryAtTheArmedCutoffTheGuardianRevertsEvenWithTheAppAlive() {
    #expect(observe(battery: BatteryReading(onAC: false, percent: 20)) == decided(.battery))
}

@Test func onBatteryAboveTheArmedCutoffTheGuardianOnlyWatches() {
    #expect(observe(battery: BatteryReading(onAC: false, percent: 21)) == [.watchApp(pid: 4242)])
}

@Test func onTheChargerALowBatteryNeverReverts() {
    #expect(observe(battery: BatteryReading(onAC: true, percent: 3)) == [.watchApp(pid: 4242)])
}

@Test func theGuardianUsesTheCutoffInTheArmedRecord() {
    let record = ArmedRecord(app: app, bootTime: boot, batteryCutoff: 40)

    #expect(
        observe(armed: record, battery: BatteryReading(onAC: false, percent: 35)).contains(
            .recordShutdown(.battery)))
}

@Test func aLowBatteryWithNothingArmedIsLeftAlone() {
    #expect(observe(armed: nil, battery: BatteryReading(onAC: false, percent: 5)).isEmpty)
}

@Test func aLowBatteryWithSleepAlreadyEnabledIsRecordedWithoutRunningAnything() {
    #expect(
        observe(sleepDisabled: false, battery: BatteryReading(onAC: false, percent: 5))
            == decided(.battery, runs: false))
}

@Test func onlyADebugGuardianHonorsTheTestCutoffOnAFullBattery() {
    let record = ArmedRecord(app: app, bootTime: boot, batteryCutoff: BatteryCutoff.testValue)
    let full = BatteryReading(onAC: false, percent: 100)

    #expect(observe(armed: record, battery: full, testMode: true).contains(.recordShutdown(.battery)))
    #expect(observe(armed: record, battery: full, testMode: false) == [.watchApp(pid: 4242)])
}

@Test(arguments: [ThermalState.serious, .critical])
func anOverheatedMacWithTheAppAliveRevertsAndRecordsThermal(thermal: ThermalState) {
    #expect(observe(thermal: thermal) == decided(.thermal))
}

@Test(arguments: [ThermalState.nominal, .fair])
func aNominalOrFairMacOnlyWatchesTheApp(thermal: ThermalState) {
    #expect(observe(thermal: thermal) == [.watchApp(pid: 4242)])
}

@Test func whenTheBatteryAndTheHeatBothFireTheReasonIsThermal() {
    #expect(
        observe(battery: BatteryReading(onAC: false, percent: 5), thermal: .critical).contains(
            .recordShutdown(.thermal)))
}

@Test func anOverheatedMacWithoutAnArmedRecordIsLeftAlone() {
    #expect(observe(armed: nil, thermal: .critical).isEmpty)
}

@Test func anAppThatDiedWhileTheMacWasOverheatedIsRecordedAsAppDied() {
    #expect(observe(running: nil, thermal: .serious).contains(.recordShutdown(.appDied)))
}

@Test func anUnreadableSleepDisabledIsNotTakenForZeroAndTheRevertStillRuns() {
    #expect(
        observe(sleepDisabled: nil, running: nil) == decided(.appDied) + [.recheckAfterGrace(armed)])
}

@Test func aPendingThermalRevertIsCarriedOutAfterTheMacCooledDown() {
    let pending = PendingRevert(reason: .thermal, record: armed)

    #expect(observe(thermal: .nominal, pending: pending) == carriedOut(.thermal))
}

@Test func aFailedRevertIsRetriedSoonerFirstThenAtMostOnceAMinute() {
    #expect((1...8).map(RevertRetry.delay(afterFailures:)) == [2, 4, 8, 16, 32, 60, 60, 60])
}

@Test func aPendingRevertWithSleepConfirmedOffIsFinishedWithoutRunningAnything() {
    let pending = PendingRevert(reason: .battery, record: armed)

    #expect(
        observe(sleepDisabled: false, battery: BatteryReading(onAC: true, percent: 90), pending: pending)
            == carriedOut(.battery, runs: false))
}

@Test func aPendingRevertIsFinishedBeforeANewerArmedRecordIsLookedAt() {
    let newer = ArmedRecord(app: ProcessIdentity(pid: 5151, startedAt: 9), bootTime: boot, batteryCutoff: 20)
    let pending = PendingRevert(reason: .appDied, record: armed)

    #expect(
        observe(armed: newer, running: newer.app, pending: pending) == carriedOut(.appDied))
}

private func recheck(
    armed record: ArmedRecord? = nil, sleepDisabled: Bool?, pending: PendingRevert? = nil
) -> [GuardianEffect] {
    recheck(
        afterClearing: armed,
        GuardianObservation(
            armed: record, sleepDisabled: sleepDisabled, process: nil, bootTime: boot, pending: pending))
}

@Test func aCloseLidCommandThatLandsAfterTheDeadAppsRecordWasClearedIsReverted() {
    #expect(recheck(sleepDisabled: true) == decided(.appDied))
}

@Test func theRecheckLeavesSleepDisabledAloneOnceANewerAppArmed() {
    let newer = ArmedRecord(app: ProcessIdentity(pid: 5151, startedAt: 9), bootTime: boot, batteryCutoff: 20)

    #expect(recheck(armed: newer, sleepDisabled: true).isEmpty)
}

@Test func theRecheckFindingSleepStillEnabledDoesNothing() {
    #expect(recheck(sleepDisabled: false).isEmpty)
}

@Test func theRecheckIsOnlyScheduledWhenTheDeadAppsCommandCouldStillLand() {
    #expect(!observe(running: nil).contains(.recheckAfterGrace(armed)))
    #expect(
        !observe(sleepDisabled: false, running: nil, bootTime: boot + 86_400).contains(
            .recheckAfterGrace(armed)))
    #expect(
        !observe(sleepDisabled: false, battery: BatteryReading(onAC: false, percent: 5)).contains(
            .recheckAfterGrace(armed)))
}
