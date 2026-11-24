/// The `sudoers` rule that lets one user toggle `disablesleep` without a password, and nothing else.
public struct HelperRule: Equatable, Sendable {
    public static let path = "/etc/sudoers.d/batizado"
    public static let commands = [
        "/usr/bin/pmset -a disablesleep 0",
        "/usr/bin/pmset -a disablesleep 1",
    ]

    public let user: String

    public init(user: String) throws(InvalidUserName) {
        guard Self.isSafe(user) else { throw InvalidUserName(user: user) }
        self.user = user
    }

    // Lowercase only: an all-caps word would parse as a sudoers alias, and every sudoers separator is excluded.
    private static func isSafe(_ user: String) -> Bool {
        let scalars = Array(user.unicodeScalars)
        guard let first = scalars.first, scalars.count <= 32 else { return false }
        let lower = UInt32(UInt8(ascii: "a"))...UInt32(UInt8(ascii: "z"))
        let digit = UInt32(UInt8(ascii: "0"))...UInt32(UInt8(ascii: "9"))
        let isStart = { (s: Unicode.Scalar) in lower.contains(s.value) || s == "_" }
        let isBody = { (s: Unicode.Scalar) in isStart(s) || digit.contains(s.value) || s == "-" || s == "." }
        return isStart(first) && scalars.allSatisfy(isBody)
    }

    public var text: String {
        lines.map { $0 + "\n" }.joined()
    }

    private var lines: [String] {
        [
            "# Installed by Batizado. Lets one user toggle pmset disablesleep, nothing else.",
            "\(user) ALL = (root) NOPASSWD: \(Self.commands.joined(separator: ", "))",
        ]
    }

    /// Runs as root. The candidate is created inside root-owned `sudoers.d` under a dotted name, which sudo
    /// skips, so nothing the user can write is ever validated or installed.
    public var installScript: String {
        let quotedLines = lines.map { "'\($0)'" }.joined(separator: " ")
        return """
            set -eu
            tmp=$(/usr/bin/mktemp /etc/sudoers.d/.batizado.XXXXXX)
            trap '/bin/rm -f "$tmp"' EXIT
            /usr/bin/printf '%s\\n' \(quotedLines) > "$tmp"
            /usr/sbin/chown root:wheel "$tmp"
            /bin/chmod 0440 "$tmp"
            /usr/sbin/visudo -cf "$tmp"
            /bin/mv -f "$tmp" \(Self.path)
            """
    }

    public static let removeScript = "/bin/rm -f \(path)"
}

public struct InvalidUserName: Error, Equatable, Sendable {
    public let user: String
}
