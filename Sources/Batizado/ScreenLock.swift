import BatizadoCore
import Foundation
import os

@MainActor
protocol ScreenLocking {
    /// Locks the screen now; false when the mechanism reported a failure.
    func lock() -> Bool
}

private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "screen-lock")

/// The default lock, unless the hidden `lockMechanism` default is set to `displaySleep`.
@MainActor
func systemScreenLock() -> any ScreenLocking {
    UserDefaults.standard.string(forKey: "lockMechanism") == "displaySleep"
        ? DisplaySleepScreenLock() : LoginFrameworkScreenLock()
}

/// `SACLockScreenImmediate` from the private login framework: no permission prompt, no user setting.
@MainActor
struct LoginFrameworkScreenLock: ScreenLocking {
    private typealias LockImmediate = @convention(c) () -> Int32

    func lock() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let framework = dlopen(path, RTLD_LAZY),
            let symbol = dlsym(framework, "SACLockScreenImmediate")
        else {
            log.error("SACLockScreenImmediate is unavailable; the screen was not locked")
            return false
        }
        let status = unsafeBitCast(symbol, to: LockImmediate.self)()
        log.notice("Locked the screen with SACLockScreenImmediate (status \(status))")
        return status == 0
    }
}

/// Sleeps the display; it only locks when "Require password" is set to "Immediately".
@MainActor
struct DisplaySleepScreenLock: ScreenLocking {
    func lock() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("pmset displaysleepnow could not run: \(error.localizedDescription, privacy: .public)")
            return false
        }
        log.notice("Slept the display with pmset displaysleepnow (exit \(process.terminationStatus))")
        return process.terminationStatus == 0
    }
}
