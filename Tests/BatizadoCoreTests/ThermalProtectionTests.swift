import Testing

@testable import BatizadoCore

@Test(arguments: [(ThermalState.nominal, false), (.fair, false), (.serious, true), (.critical, true)])
func onlySeriousAndCriticalTurnTheModeOff(state: ThermalState, fires: Bool) {
    #expect(state.isOverheated == fires)
}

@Test(arguments: [
    (UInt64(0), ThermalState.nominal), (1, .fair), (2, .serious), (3, .critical), (4, .critical),
    (9, .critical),
])
func theSystemPressureLevelMapsToAThermalState(level: UInt64, state: ThermalState) {
    #expect(ThermalState(pressureLevel: level) == state)
}

private func at(_ thermal: ThermalState, _ state: AppState) -> AppState {
    reduce(state, .thermalChanged(thermal)).state
}

@Test(arguments: [ThermalState.serious, .critical])
func closedLidIsRefusedWithAnExplanationWhileTheMacIsOverheated(thermal: ThermalState) {
    let (state, effects) = reduce(at(thermal, withRule(running())), .setClosedLid(true))

    #expect(effects.isEmpty)
    #expect(state.notice == .overheated(thermal))
    #expect(!state.keepAwake)
}

@Test func aFairThermalStateDoesNotRefuseClosedLid() {
    #expect(
        reduce(at(.fair, withRule(running())), .setClosedLid(true)).effects.contains(.arm(batteryCutoff: 20)))
}

@Test func whenTheHeatAndTheBatteryWouldBothRefuseTheExplanationIsTheHeat() {
    let lowBattery = reduce(withRule(running()), .batteryChanged(BatteryReading(onAC: false, percent: 5)))
        .state

    #expect(reduce(at(.serious, lowBattery), .setClosedLid(true)).state.notice == .overheated(.serious))
}

@Test func aCrashIsNotRestoredWhileTheMacIsOverheated() {
    let (state, effects) = relaunch(
        closedLidOn().preferences, readings: [.thermalChanged(.critical)], reason: .reboot)

    #expect(!effects.contains(.arm(batteryCutoff: 20)))
    #expect(state.notice == .overheated(.critical))
}

@Test func theThermalProtectionTurnsOffClosedLidAndKeepAwakeAndNotifies() {
    let (state, effects) = reduce(closedLidOn(), .shutdownRecorded(.thermal))

    #expect(state.lastShutdown == .thermal)
    #expect(!state.keepAwake)
    #expect(state.closedLidRequest == false)
    #expect(effects.contains(.release(.systemIdle)))
    #expect(effects.contains(.setSleepDisabled(false)))
    #expect(effects.contains(.notify(.thermal)))
}

@Test func coolingDownTurnsNothingOn() {
    let reverted = reduce(at(.serious, closedLidOn()), .shutdownRecorded(.thermal)).state

    let (state, effects) = reduce(reverted, .thermalChanged(.nominal))

    #expect(effects.isEmpty)
    #expect(!state.keepAwake)
    #expect(state.lastShutdown == .thermal)
}

@Test func thermalIsAStickyReason() {
    #expect(ShutdownReason.thermal.isSticky)
}
