import Testing

@testable import BatizadoCore

@Test func guardianAgentPointsAtTheGuardianInsideTheGivenBundle() {
    let agent = LaunchAgent.guardian(bundlePath: "/Applications/Batizado.app")

    #expect(agent.label == "io.github.victorhugobn.batizado.guardian")
    #expect(agent.fileName == "io.github.victorhugobn.batizado.guardian.plist")
    #expect(
        agent.plist == """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>Label</key>
            \t<string>io.github.victorhugobn.batizado.guardian</string>
            \t<key>ProgramArguments</key>
            \t<array>
            \t\t<string>/Applications/Batizado.app/Contents/MacOS/BatizadoGuardian</string>
            \t</array>
            \t<key>RunAtLoad</key>
            \t<true/>
            \t<key>KeepAlive</key>
            \t<true/>
            \t<key>LimitLoadToSessionType</key>
            \t<string>Aqua</string>
            \t<key>AssociatedBundleIdentifiers</key>
            \t<string>io.github.victorhugobn.batizado</string>
            </dict>
            </plist>

            """)
}

@Test func bundlePathsAreEscapedForXML() {
    let agent = LaunchAgent.guardian(bundlePath: "/Users/a/Tom & <Jerry>/Batizado.app")

    #expect(
        agent.plist.contains(
            "<string>/Users/a/Tom &amp; &lt;Jerry&gt;/Batizado.app/Contents/MacOS/BatizadoGuardian</string>"))
}

@Test func aMissingAgentIsWrittenAndLoaded() {
    #expect(LaunchAgent.sync(installed: nil, wanted: "new", loaded: false) == [.write, .load])
}

@Test func anAgentForAnotherPathIsRewrittenAndReloaded() {
    #expect(LaunchAgent.sync(installed: "old", wanted: "new", loaded: true) == [.write, .unload, .load])
}

@Test func aCurrentAgentThatIsNotLoadedIsOnlyLoaded() {
    #expect(LaunchAgent.sync(installed: "same", wanted: "same", loaded: false) == [.load])
}

@Test func aCurrentLoadedAgentIsLeftAlone() {
    #expect(LaunchAgent.sync(installed: "same", wanted: "same", loaded: true).isEmpty)
}

@Test func loginAgentOpensTheGivenBundleOnceAtLogin() {
    let agent = LaunchAgent.login(bundlePath: "/Applications/Batizado.app")

    #expect(agent.label == "io.github.victorhugobn.batizado.login")
    #expect(agent.fileName == "io.github.victorhugobn.batizado.login.plist")
    #expect(
        agent.plist == """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>Label</key>
            \t<string>io.github.victorhugobn.batizado.login</string>
            \t<key>ProgramArguments</key>
            \t<array>
            \t\t<string>/usr/bin/open</string>
            \t\t<string>/Applications/Batizado.app</string>
            \t</array>
            \t<key>RunAtLoad</key>
            \t<true/>
            \t<key>KeepAlive</key>
            \t<false/>
            \t<key>LimitLoadToSessionType</key>
            \t<string>Aqua</string>
            \t<key>AssociatedBundleIdentifiers</key>
            \t<string>io.github.victorhugobn.batizado</string>
            </dict>
            </plist>

            """)
}

@Test func turningLaunchAtLoginOnOnlyWritesTheAgentForTheNextLogin() {
    #expect(LaunchAgent.setLaunchAtLogin(true, loaded: false) == [.write])
}

@Test func turningLaunchAtLoginOffRemovesTheAgentAndUnloadsItIfLoaded() {
    #expect(LaunchAgent.setLaunchAtLogin(false, loaded: true) == [.unload, .remove])
    #expect(LaunchAgent.setLaunchAtLogin(false, loaded: false) == [.remove])
}

@Test func aLoginAgentForAnotherPathIsPointedAtThisBundleWithoutLoadingIt() {
    #expect(LaunchAgent.repairLogin(installed: "old", wanted: "new") == [.write])
}

@Test func noLoginAgentStaysNoneAndACurrentOneIsLeftAlone() {
    #expect(LaunchAgent.repairLogin(installed: nil, wanted: "new").isEmpty)
    #expect(LaunchAgent.repairLogin(installed: "same", wanted: "same").isEmpty)
}
