import AppKit
import BatizadoCore
import os

@MainActor
protocol HelperRuleManaging {
    func isInstalled() -> Bool
    /// Explains what will be installed, then installs it through the administrator password window.
    func install() -> AdministratorOutcome
    func remove() -> AdministratorOutcome
    /// Calls back whenever the rule's directory changes, with whether the rule is there.
    func watch(onChange: @escaping @MainActor (Bool) -> Void)
}

@MainActor
final class SystemHelperRule: HelperRuleManaging {
    private static let directory = "/etc/sudoers.d"
    private static let userCancelled = -128

    private var source: (any DispatchSourceFileSystemObject)?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "helper-rule")

    // Root-owned is all an unprivileged process can check: the file itself is not readable.
    func isInstalled() -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: HelperRule.path)
        return (attributes?[.ownerAccountID] as? NSNumber)?.intValue == 0
    }

    func install() -> AdministratorOutcome {
        let rule: HelperRule
        do {
            rule = try HelperRule(user: NSUserName())
        } catch {
            return .failed("The user name \"\(error.user)\" cannot be used in a sudoers rule.")
        }
        guard confirm(for: rule) else { return .cancelled }
        let outcome = runAsAdministrator(
            rule.installScript,
            prompt: "Batizado wants to install its helper rule so Closed lid can turn sleep off and on."
        )
        if outcome == .succeeded, !isInstalled() {
            return .failed("The rule was not found at \(HelperRule.path) after installing it.")
        }
        return outcome
    }

    func remove() -> AdministratorOutcome {
        runAsAdministrator(HelperRule.removeScript, prompt: "Batizado wants to remove its helper rule.")
    }

    func watch(onChange: @escaping @MainActor (Bool) -> Void) {
        let descriptor = open(Self.directory, O_EVTONLY)
        guard descriptor >= 0 else {
            log.error("Could not watch \(Self.directory, privacy: .public): errno \(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                onChange(self.isInstalled())
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func confirm(for rule: HelperRule) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Closed lid needs a helper rule"
        alert.informativeText = """
            Batizado will install \(HelperRule.path), owned by root and read-only. It lets the user \
            "\(rule.user)" run exactly these two commands without a password:

            \(HelperRule.commands.joined(separator: "\n"))

            Nothing else runs as root. macOS will ask for an administrator password once. You can remove the \
            rule at any time with "Remove helper rule".
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runAsAdministrator(_ script: String, prompt: String) -> AdministratorOutcome {
        let source = administratorAppleScript(running: script, prompt: prompt)
        guard let appleScript = NSAppleScript(source: source) else {
            return .failed("Could not build the administrator script.")
        }
        NSApp.activate(ignoringOtherApps: true)
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        guard let error else { return .succeeded }
        if error[NSAppleScript.errorNumber] as? Int == Self.userCancelled { return .cancelled }
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
        log.error("Administrator script failed: \(message, privacy: .public)")
        return .failed(message)
    }
}
