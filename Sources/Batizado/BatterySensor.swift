import BatizadoCore
import BatizadoSystem
import os

@MainActor
protocol BatterySensing {
    /// Reports the battery reading at once, then again each time it changes; nil without a battery.
    func start(onChange: @escaping @MainActor (BatteryReading?) -> Void)
}

/// Re-reads the power sources on each IOKit power source notification (and, in debug builds, the simulation).
@MainActor
final class SystemBatterySensor: BatterySensing {
    private var last: BatteryReading??
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "battery")

    func start(onChange: @escaping @MainActor (BatteryReading?) -> Void) {
        let report: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let reading = PowerSource.reading
            guard self.last != .some(reading) else { return }
            self.last = .some(reading)
            let text = reading.map { "\($0.percent)% on \($0.onAC ? "AC" : "battery")" } ?? "no battery"
            self.log.notice("Battery: \(text, privacy: .public)")
            onChange(reading)
        }
        if BuildMode.testMode { log.notice("Debug build: the low battery test mode is available") }
        report()
        PowerSource.observe(report)
    }
}
