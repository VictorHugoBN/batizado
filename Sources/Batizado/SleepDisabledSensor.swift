import BatizadoCore
import BatizadoSystem
import Foundation
import notify
import os

@MainActor
protocol SleepDisabledSensing {
    /// Reports the current value at once, then again every time the system may have changed it; nil when the
    /// value could not be read.
    func start(onChange: @escaping @MainActor (Bool?) -> Void)
    /// Reads the value now, without waiting for a change notification; nil when it could not be read.
    func current() -> Bool?
}

@MainActor
final class SystemSleepDisabledSensor: SleepDisabledSensing {
    // Posted by powerd when power settings change; com.apple.system names only accept posts from root.
    private static let settingsChanged = "com.apple.system.powermanagement.prefschange"

    private var token: Int32 = 0
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "sleep-disabled")

    func start(onChange: @escaping @MainActor (Bool?) -> Void) {
        onChange(current())
        let status = notify_register_dispatch(Self.settingsChanged, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                onChange(self.current())
            }
        }
        if status != NOTIFY_STATUS_OK {
            log.error("Could not observe \(Self.settingsChanged, privacy: .public): \(status)")
        }
    }

    func current() -> Bool? {
        SystemFacts.sleepDisabled
    }
}
