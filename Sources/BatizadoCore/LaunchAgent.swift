/// A plain plist for `~/Library/LaunchAgents`; `SMAppService` breaks on every ad-hoc rebuild.
public struct LaunchAgent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case write
        case unload
        case load
    }

    public let label: String
    public let program: String

    public static func guardian(bundlePath: String) -> LaunchAgent {
        LaunchAgent(
            label: AppInfo.guardianIdentifier,
            program: bundlePath + "/Contents/MacOS/" + AppInfo.name + "Guardian")
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
        \t\t<string>\(xmlEscaped(program))</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<true/>
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
