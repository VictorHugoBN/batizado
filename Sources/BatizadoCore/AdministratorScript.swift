/// AppleScript source that runs a fixed shell script through the native administrator password window.
public func administratorAppleScript(running script: String, prompt: String) -> String {
    "do shell script \(appleScriptLiteral(script)) with prompt \(appleScriptLiteral(prompt))"
        + " with administrator privileges"
}

private func appleScriptLiteral(_ text: String) -> String {
    var escaped = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": escaped += "\\\\"
        case "\"": escaped += "\\\""
        case "\n": escaped += "\\n"
        case "\r": escaped += "\\r"
        default: escaped.unicodeScalars.append(scalar)
        }
    }
    return "\"\(escaped)\""
}
