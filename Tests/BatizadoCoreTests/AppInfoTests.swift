import Testing

@testable import BatizadoCore

@Test func guardianIdentifierIsNamespacedUnderTheApp() {
    #expect(AppInfo.guardianIdentifier.hasPrefix(AppInfo.bundleIdentifier + "."))
}
