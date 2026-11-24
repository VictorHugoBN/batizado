import Testing

@testable import BatizadoCore

private let me = ProcessIdentity(pid: 500, startedAt: 2_000)

@Test func aCopyAloneKeepsRunning() {
    #expect(!me.yields(to: [me]))
}

@Test func aCopyStartedAfterAnotherOneExits() {
    #expect(me.yields(to: [me, ProcessIdentity(pid: 900, startedAt: 1_000)]))
}

@Test func theOlderCopyKeepsRunningWhenANewerOneAppears() {
    #expect(!me.yields(to: [me, ProcessIdentity(pid: 100, startedAt: 3_000)]))
}

@Test func twoCopiesStartedInTheSameMicrosecondKeepTheLowerPid() {
    #expect(me.yields(to: [ProcessIdentity(pid: 499, startedAt: 2_000)]))
    #expect(!me.yields(to: [ProcessIdentity(pid: 501, startedAt: 2_000)]))
}
