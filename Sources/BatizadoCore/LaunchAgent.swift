/// A plain plist for `~/Library/LaunchAgents`; `SMAppService` breaks on every ad-hoc rebuild.
public struct LaunchAgent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case write
        case unload
        case load
        case remove
    }

    public let label: String
    public let arguments: [String]
    /// The guardian is restarted whenever it exits; the app is started once and stays quit after Quit.
    public let keepAlive: Bool

    public var program: String { arguments[0] }

    public static func guardian(bundlePath: String) -> LaunchAgent {
        LaunchAgent(
            label: AppInfo.guardianIdentifier,
            arguments: [bundlePath + "/Contents/MacOS/" + AppInfo.name + "Guardian"], keepAlive: true)
    }

    // Through `open`, so LaunchServices starts the app like a Finder launch and never a second copy of it.
    public static func login(bundlePath: String) -> LaunchAgent {
        LaunchAgent(
            label: AppInfo.loginIdentifier, arguments: ["/usr/bin/open", bundlePath], keepAlive: false)
    }

    public var fileName: String { label + ".plist" }

    public var plist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(xmlEscaped(label))</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \(arguments.map { "\t\t<string>\(xmlEscaped($0))</string>\n" }.joined())\
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<\(keepAlive)/>
        \t<key>LimitLoadToSessionType</key>
        \t<string>Aqua</string>
        \t<key>AssociatedBundleIdentifiers</key>
        \t<string>\(AppInfo.bundleIdentifier)</string>
        </dict>
        </plist>

        """
    }

    /// What to do so the loaded agent matches `wanted`, given the file on disk and whether launchd has it.
    public static func sync(installed: String?, wanted: String, loaded: Bool) -> [Action] {
        if installed == wanted { return loaded ? [] : [.load] }
        return loaded ? [.write, .unload, .load] : [.write, .load]
    }

    /// Turning it on only writes the file: loading a run-at-load agent now would open the app right away.
    public static func setLaunchAtLogin(_ on: Bool, loaded: Bool) -> [Action] {
        guard !on else { return [.write] }
        return loaded ? [.unload, .remove] : [.remove]
    }

    /// At launch, a login agent left by a copy of the app elsewhere is pointed at this one; none stays none.
    public static func repairLogin(installed: String?, wanted: String) -> [Action] {
        guard let installed, installed != wanted else { return [] }
        return [.write]
    }
}

private func xmlEscaped(_ text: String) -> String {
    var escaped = ""
    for character in text {
        switch character {
        case "&": escaped += "&amp;"
        case "<": escaped += "&lt;"
        case ">": escaped += "&gt;"
        default: escaped.append(character)
        }
    }
    return escaped
}
