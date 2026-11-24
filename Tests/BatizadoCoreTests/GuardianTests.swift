import Testing

@testable import BatizadoCore

private let app = ProcessIdentity(pid: 4242, startedAt: 1_700_000_000_123_456)
private let boot: Int64 = 1_699_990_000
private let armed = ArmedRecord(app: app, bootTime: boot)

private func observe(
    armed record: ArmedRecord? = armed,
    sleepDisabled: Bool = true,
    running: ProcessIdentity? = app,
    bootTime: Int64 = boot
) -> [GuardianEffect] {
    reconcile(
        GuardianObservation(armed: record, sleepDisabled: sleepDisabled, process: running, bootTime: bootTime)
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
