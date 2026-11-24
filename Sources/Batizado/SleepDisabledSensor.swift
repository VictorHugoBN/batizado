import BatizadoCore
import Foundation
import IOKit
import notify
import os

@MainActor
protocol SleepDisabledSensing {
    /// Reports the current value at once, then again every time the system may have changed it.
    func start(onChange: @escaping @MainActor (Bool) -> Void)
}

@MainActor
final class SystemSleepDisabledSensor: SleepDisabledSensing {
    // Posted by powerd when power settings change; com.apple.system names only accept posts from root.
    private static let settingsChanged = "com.apple.system.powermanagement.prefschange"

    private var token: Int32 = 0
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "sleep-disabled")

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        onChange(read())
        let status = notify_register_dispatch(Self.settingsChanged, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                onChange(self.read())
            }
        }
        if status != NOTIFY_STATUS_OK {
            log.error("Could not observe \(Self.settingsChanged, privacy: .public): \(status)")
        }
    }

    // The kernel's root power domain holds the value it actually enforces on lid close.
    private func read() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else {
            log.error("IOPMrootDomain not found; reporting SleepDisabled as 0")
            return false
        }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(
            root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        guard let disabled = value as? Bool else {
            log.error("IOPMrootDomain has no SleepDisabled; reporting 0")
            return false
        }
        log.info("SleepDisabled is \(disabled ? 1 : 0)")
        return disabled
    }
}
