import Testing

@testable import BatizadoCore

private let app = ProcessIdentity(pid: 4242, startedAt: 1_700_000_000_123_456)
private let boot: Int64 = 1_699_990_000
private let armed = ArmedRecord(app: app, bootTime: boot, batteryCutoff: 20)

private func observe(
    armed record: ArmedRecord? = armed,
    sleepDisabled: Bool = true,
    running: ProcessIdentity? = app,
    bootTime: Int64 = boot,
    battery: BatteryReading? = nil,
    thermal: ThermalState? = nil,
    testMode: Bool = false
) -> [GuardianEffect] {
    reconcile(
        GuardianObservation(
            armed: record, sleepDisabled: sleepDisabled, process: running, bootTime: bootTime,
            battery: battery,
            thermal: thermal,
            testMode: testMode)
    )
}

@Test func armedWithTheAppAliveOnlyWatchesIt() {
    #expect(observe() == [.watchApp(pid: 4242)])
}

@Test func armedWithTheAppDeadRevertsAndRecordsAppDied() {
    #expect(
        observe(running: nil) == [
            .revertSleepDisabled, .recordShutdown(.appDied), .clearArmed(armed), .signalApp,
        ])
}

@Test func aRecycledPidIsNotMistakenForTheApp() {
    let stranger = ProcessIdentity(pid: 4242, startedAt: 1_700_000_999_000_000)

    #expect(observe(running: stranger).first == .revertSleepDisabled)
}

@Test func armedBeforeARestartRecordsReboot() {
    #expect(observe(running: nil, bootTime: boot + 86_400).contains(.recordShutdown(.reboot)))
}

@Test func nothingArmedNeverTouchesSleepDisabledSetOutsideTheApp() {
    #expect(observe(armed: nil, sleepDisabled: true, running: nil).isEmpty)
}

@Test func aStaleRecordWithSleepAlreadyEnabledIsClearedAndReportedWithoutRunningAnything() {
    #expect(
        observe(sleepDisabled: false, running: nil) == [
            .recordShutdown(.appDied), .clearArmed(armed), .signalApp,
        ])
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
    #expect(
        observe(battery: BatteryReading(onAC: false, percent: 20)) == [
            .revertSleepDisabled, .recordShutdown(.battery), .clearArmed(armed), .signalApp,
        ])
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
        observe(sleepDisabled: false, battery: BatteryReading(onAC: false, percent: 5)) == [
            .recordShutdown(.battery), .clearArmed(armed), .signalApp,
        ])
}

@Test func onlyADebugGuardianHonorsTheTestCutoffOnAFullBattery() {
    let record = ArmedRecord(app: app, bootTime: boot, batteryCutoff: BatteryCutoff.testValue)
    let full = BatteryReading(onAC: false, percent: 100)

    #expect(observe(armed: record, battery: full, testMode: true).contains(.recordShutdown(.battery)))
    #expect(observe(armed: record, battery: full, testMode: false) == [.watchApp(pid: 4242)])
}

@Test(arguments: [ThermalState.serious, .critical])
func anOverheatedMacWithTheAppAliveRevertsAndRecordsThermal(thermal: ThermalState) {
    #expect(
        observe(thermal: thermal) == [
            .revertSleepDisabled, .recordShutdown(.thermal), .clearArmed(armed), .signalApp,
        ])
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
