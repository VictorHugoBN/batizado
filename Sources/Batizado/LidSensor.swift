import BatizadoCore
import IOKit
import os

@MainActor
protocol LidSensing {
    /// Reports whether the lid is closed at once, then again every time it changes.
    func start(onChange: @escaping @MainActor (Bool) -> Void)
}

/// Reads `AppleClamshellState` from the root power domain and re-reads it on every message the domain sends.
@MainActor
final class SystemLidSensor: LidSensing {
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var onChange: (@MainActor (Bool) -> Void)?
    private var last: Bool?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "lid")

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        report()
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else {
            log.error("IOPMrootDomain not found; lid changes will not be seen")
            return
        }
        defer { IOObjectRelease(root) }
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        let status = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest,
            { refcon, _, _, _ in
                guard let refcon else { return }
                MainActor.assumeIsolated {
                    Unmanaged<SystemLidSensor>.fromOpaque(refcon).takeUnretainedValue().report()
                }
            },
            Unmanaged.passUnretained(self).toOpaque(), &notifier)
        if status != KERN_SUCCESS {
            log.error("Could not observe the lid: \(status)")
        }
    }

    private func report() {
        guard let closed = Self.lidClosed(), closed != last else { return }
        last = closed
        log.notice("Lid is \(closed ? "closed" : "open", privacy: .public)")
        onChange?(closed)
    }

    /// Nil on a Mac without a lid, where `AppleClamshellState` does not exist.
    private static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(
            root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
