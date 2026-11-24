import BatizadoCore
import CoreGraphics
import os

@MainActor
protocol ExternalDisplaySensing {
    /// Reports whether any display other than the built-in one is active, at once and on every change.
    func start(onChange: @escaping @MainActor (Bool) -> Void)
}

@MainActor
final class SystemExternalDisplaySensor: ExternalDisplaySensing {
    private var onChange: (@MainActor (Bool) -> Void)?
    private var last: Bool?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "displays")

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        report()
        let status = CGDisplayRegisterReconfigurationCallback(
            { _, flags, refcon in
                // The list is only settled once the reconfiguration has finished.
                guard let refcon, !flags.contains(.beginConfigurationFlag) else { return }
                let sensor = Unmanaged<SystemExternalDisplaySensor>.fromOpaque(refcon)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { sensor.takeUnretainedValue().report() }
                }
            },
            Unmanaged.passUnretained(self).toOpaque())
        if status != .success {
            log.error("Could not observe display changes: \(status.rawValue)")
        }
    }

    private func report() {
        let active = Self.externalDisplayActive()
        guard active != last else { return }
        last = active
        log.notice("External display active: \(active ? "yes" : "no", privacy: .public)")
        onChange?(active)
    }

    private static func externalDisplayActive() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
