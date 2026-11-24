import Testing

@testable import BatizadoCore

@Test func ruleAllowsOnlyTheTwoPmsetCommandsForTheUser() throws {
    let rule = try HelperRule(user: "victor")

    #expect(
        rule.text == """
            # Installed by Batizado. Lets one user toggle pmset disablesleep, nothing else.
            victor ALL = (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1

            """)
}

@Test(
    arguments: [
        "", "victor ALL", "victor,root", "victor\nroot ALL=(ALL) ALL", "victor:x", "a=b", "#501", "%admin",
        "VICTOR", "Victor", "-victor", ".victor", "victor'", "victor\"", "vic\\tor", "víctor", "ALL",
        String(repeating: "a", count: 33),
    ])
func ruleRejectsUserNamesOutsideTheAllowedCharacters(user: String) {
    #expect(throws: InvalidUserName(user: user)) { try HelperRule(user: user) }
}

@Test(arguments: [
    "victor", "_victor", "victor.nascimento", "victor-n", "victor_2", String(repeating: "a", count: 32),
])
func ruleAcceptsOrdinaryShortNames(user: String) throws {
    #expect(try HelperRule(user: user).user == user)
}

@Test func installScriptBuildsAndChecksTheCandidateWhereOnlyRootCanWriteThenMovesIt() throws {
    let script = try HelperRule(user: "victor").installScript

    #expect(
        script == """
            set -eu
            tmp=$(/usr/bin/mktemp /etc/sudoers.d/.batizado.XXXXXX)
            trap '/bin/rm -f "$tmp"' EXIT
            /usr/bin/printf '%s\\n' '# Installed by Batizado. Lets one user toggle pmset disablesleep, nothing else.' 'victor ALL = (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' > "$tmp"
            /usr/sbin/chown root:wheel "$tmp"
            /bin/chmod 0440 "$tmp"
            /usr/sbin/visudo -cf "$tmp"
            /bin/mv -f "$tmp" /etc/sudoers.d/batizado
            """)
}

@Test func removeScriptDeletesOnlyTheRuleFile() {
    #expect(HelperRule.removeScript == "/bin/rm -f /etc/sudoers.d/batizado")
}
