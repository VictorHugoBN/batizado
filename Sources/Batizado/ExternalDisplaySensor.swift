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
    private var registered = false
    // The callback holds this box, not self, so it can never reach a released sensor.
    private lazy var refcon = Unmanaged.passRetained(WeakSensor(self)).toOpaque()

    isolated deinit {
        guard registered else { return }
        CGDisplayRemoveReconfigurationCallback(displaysReconfigured, refcon)
        Unmanaged<WeakSensor>.fromOpaque(refcon).release()
    }

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        report()
        registered = CGDisplayRegisterReconfigurationCallback(displaysReconfigured, refcon) == .success
        if !registered {
            log.error("Could not observe display changes")
        }
    }

    fileprivate func report() {
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

private final class WeakSensor: @unchecked Sendable {
    weak var sensor: SystemExternalDisplaySensor?
    init(_ sensor: SystemExternalDisplaySensor) { self.sensor = sensor }
}

private func displaysReconfigured(
    _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ refcon: UnsafeMutableRawPointer?
) {
    // The list is only settled once the reconfiguration has finished.
    guard let refcon, !flags.contains(.beginConfigurationFlag) else { return }
    let box = Unmanaged<WeakSensor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { box.sensor?.report() }
    }
}
