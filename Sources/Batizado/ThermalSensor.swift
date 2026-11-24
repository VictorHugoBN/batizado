import BatizadoCore
import BatizadoSystem
import os

@MainActor
protocol ThermalSensing {
    /// Reports the thermal state at once, then again each time it changes; stops when the sensor is released.
    func start(onChange: @escaping @MainActor (ThermalState) -> Void)
}

/// Re-reads the thermal state on each system notification (and, in debug builds, the simulation).
@MainActor
final class SystemThermalSensor: ThermalSensing {
    private var last: ThermalState?
    private var subscription: DarwinSubscription?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "thermal")

    func start(onChange: @escaping @MainActor (ThermalState) -> Void) {
        let report: @MainActor () -> Void = { [weak self] in
            guard let self, let state = ThermalPressure.state, state != self.last else { return }
            self.last = state
            self.log.notice("Thermal state: \(state.rawValue, privacy: .public)")
            onChange(state)
        }
        if BuildMode.testMode { log.notice("Debug build: the thermal test mode is available") }
        report()
        subscription = ThermalPressure.observe(report)
    }
}
