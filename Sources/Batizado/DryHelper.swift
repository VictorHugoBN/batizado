#if DEBUG
    import BatizadoCore
    import BatizadoSystem
    import Foundation
    import os

    /// Debug builds only, and only when launched with `BATIZADO_DEBUG_DRY_HELPER=1` in the environment: the
    /// helper rule reads as installed and the two `pmset` commands are logged instead of run, so the guardian
    /// handshake can be exercised without sudo or a password window. `SleepDisabled` is still read for real.
    enum DryHelper {
        static var isRequested: Bool {
            ProcessInfo.processInfo.environment["BATIZADO_DEBUG_DRY_HELPER"] == "1"
        }

        static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "dry-helper")

        /// Drive the same events as the popover's rows, by name: `...debug-closed-lid-on|off` and
        /// `...debug-remove-helper-rule`.
        static let events: [(String, AppEvent)] = [
            ("closed-lid-on", .setClosedLid(true)), ("closed-lid-off", .setClosedLid(false)),
            ("remove-helper-rule", .removeHelperRule),
        ]
    }

    @MainActor
    struct DrySleepDisabledSwitch: SleepDisabledSwitching {
        func set(_ disabled: Bool) -> Bool {
            DryHelper.log.notice("Dry run: would run disablesleep \(disabled ? 1 : 0)")
            return true
        }
    }

    @MainActor
    struct DryHelperRule: HelperRuleManaging {
        func isInstalled() -> Bool { true }
        func install() -> AdministratorOutcome { .succeeded }
        func remove() -> AdministratorOutcome {
            DryHelper.log.notice("Dry run: would remove the helper rule")
            return .succeeded
        }
        func watch(onChange: @escaping @MainActor (Bool) -> Void) {}
    }
#endif
