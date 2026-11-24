import Foundation
import Testing

@testable import BatizadoCore

@Test func guardianIdentifierIsNamespacedUnderTheApp() {
    #expect(AppInfo.guardianIdentifier.hasPrefix(AppInfo.bundleIdentifier + "."))
}

@Test func sponsorLinkPointsAtTheFundingAccount() throws {
    let funding = try String(
        contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../.github/FUNDING.yml").standardized,
        encoding: .utf8)
    let account = try #require(funding.split(separator: "\n").first { $0.hasPrefix("github:") })
        .dropFirst("github:".count).trimmingCharacters(in: .whitespaces)

    #expect(AppInfo.sponsorURL == "https://github.com/sponsors/\(account)")
}
