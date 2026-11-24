import BatizadoCore
import Foundation
import IOKit.ps
import os

/// Debug builds only: the low battery test mode exists nowhere in a release build.
public enum BuildMode {
    #if DEBUG
        public static let testMode = true
    #else
        public static let testMode = false
    #endif
}

/// The internal battery and the power source feeding the Mac, read from IOKit's power sources.
public enum PowerSource {
    /// IOKit posts this on any power source change: charger in or out and every change of the battery level.
    private static let anyChange = "com.apple.system.powersources"

    #if DEBUG
        /// Post after writing or removing `debug-battery.json` to make both processes read it again.
        public static let simulatedChange = AppInfo.bundleIdentifier + ".debug-battery-changed"
    #endif

    /// Nil on a Mac without an internal battery.
    public static var reading: BatteryReading? {
        #if DEBUG
            if let simulated = simulatedReading { return simulated }
        #endif
        return systemReading
    }

    /// Calls `handler` on the main queue after each power source change. Event-driven; nothing polls.
    @MainActor
    public static func observe(_ handler: @escaping @MainActor () -> Void) {
        DarwinNotification.observe(anyChange, handler: handler)
        #if DEBUG
            DarwinNotification.observe(simulatedChange, handler: handler)
        #endif
    }

    private static var systemReading: BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let percent = Int((Double(current) * 100 / Double(maximum)).rounded())
            return BatteryReading(onAC: providing == kIOPMACPowerKey, percent: percent)
        }
        return nil
    }

    #if DEBUG
        /// `~/Library/Application Support/Batizado/debug-battery.json`, e.g. `{"onAC":false,"percent":15}`.
        private static var simulatedReading: BatteryReading? {
            let file = SharedState().directory.appending(path: "debug-battery.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            guard let reading = try? JSONDecoder().decode(BatteryReading.self, from: data) else {
                Logger(subsystem: AppInfo.bundleIdentifier, category: "battery").error(
                    "Ignoring unreadable \(file.path, privacy: .public)")
                return nil
            }
            return reading
        }
    #endif
}
