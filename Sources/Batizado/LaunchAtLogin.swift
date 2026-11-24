import BatizadoCore
import Foundation
import os

@MainActor
protocol LaunchAtLoginManaging {
    /// False when the app does not run from a stable .app, so there is nothing to open at login.
    var isAvailable: Bool { get }
    /// On only when the login agent file exists and opens this bundle; read from disk each time.
    func isEnabled() -> Bool
    /// At launch: a login agent left for another copy of the app is pointed at this one.
    func repair()
    func set(_ on: Bool)
}

@MainActor
final class SystemLaunchAtLogin: LaunchAtLoginManaging {
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "launch-at-login")
    private lazy var agent: LaunchAgent? = UserAgents.stableBundlePath(log: log).map(LaunchAgent.login)

    var isAvailable: Bool { agent != nil }

    func isEnabled() -> Bool {
        guard let agent else { return false }
        return UserAgents.installed(agent) == agent.plist
    }

    func repair() {
        guard let agent else { return }
        for action in LaunchAgent.repairLogin(installed: UserAgents.installed(agent), wanted: agent.plist) {
            _ = UserAgents.perform(action, agent, log: log)
        }
    }

    func set(_ on: Bool) {
        guard let agent else { return }
        let loaded = !on && UserAgents.isLoaded(agent, log: log)
        for action in LaunchAgent.setLaunchAtLogin(on, loaded: loaded) {
            _ = UserAgents.perform(action, agent, log: log)
        }
        log.notice("Launch at login is \(self.isEnabled() ? "on" : "off", privacy: .public)")
    }
}
