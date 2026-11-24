import Testing

@testable import BatizadoCore

@Test func administratorScriptEscapesQuotesBackslashesAndNewlinesForAppleScript() {
    let source = administratorAppleScript(running: "a \"b\" 'c' \\n\nd", prompt: "Say \"hi\"")

    #expect(
        source
            == #"do shell script "a \"b\" 'c' \\n\nd" with prompt "Say \"hi\"" with administrator privileges"#
    )
}
