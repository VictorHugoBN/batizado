import BatizadoCore
import Foundation
import notify
import os

/// The system's thermal state, read from the notify(3) state that macOS publishes with each change. This is
/// libnotify, not AppKit, so it reaches the guardian's plain run loop too.
public enum ThermalPressure {
    private static let changed = String(cString: kOSThermalNotificationPressureLevelName)
    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "thermal")

    #if DEBUG
        /// Post after writing or removing `debug-thermal.json` to make both processes read it again.
        public static let simulatedChange = AppInfo.bundleIdentifier + ".debug-thermal-changed"
    #endif

    /// Nil if the system's state cannot be read.
    public static var state: ThermalState? {
        #if DEBUG
            if let simulated = simulatedState { return simulated }
        #endif
        return systemState
    }

    /// Calls `handler` on the main queue after each thermal state change, until the result is released.
    @MainActor
    public static func observe(_ handler: @escaping @MainActor () -> Void) -> DarwinSubscription {
        #if DEBUG
            DarwinSubscription([changed, simulatedChange], handler: handler)
        #else
            DarwinSubscription([changed], handler: handler)
        #endif
    }

    private static var systemState: ThermalState? {
        var token: Int32 = 0
        guard notify_register_check(changed, &token) == NOTIFY_STATUS_OK else {
            log.error("Could not register for the thermal pressure level")
            return nil
        }
        defer { notify_cancel(token) }
        var level: UInt64 = 0
        guard notify_get_state(token, &level) == NOTIFY_STATUS_OK else {
            log.error("Could not read the thermal pressure level")
            return nil
        }
        return ThermalState(pressureLevel: level)
    }

    #if DEBUG
        private struct Simulation: Decodable {
            let state: ThermalState
        }

        /// `~/Library/Application Support/Batizado/debug-thermal.json`, e.g. `{"state":"serious"}`.
        private static var simulatedState: ThermalState? {
            let file = SharedState().directory.appending(path: "debug-thermal.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            guard let simulation = try? JSONDecoder().decode(Simulation.self, from: data) else {
                log.error("Ignoring unreadable \(file.path, privacy: .public)")
                return nil
            }
            return simulation.state
        }
    #endif
}
