import Foundation
import Testing

@testable import BatizadoCore

@Test func aRecordWrittenBeforeTheCutoffExistedUsesTheDefaultCutoff() throws {
    let json = #"{"app":{"pid":4242,"startedAt":1700000000123456},"bootTime":1699990000}"#

    let record = try JSONDecoder().decode(ArmedRecord.self, from: Data(json.utf8))

    #expect(record.batteryCutoff == BatteryCutoff.standard)
}

@Test func theCutoffSurvivesTheRoundTripThroughTheFile() throws {
    let record = ArmedRecord(
        app: ProcessIdentity(pid: 7, startedAt: 1), bootTime: 2, batteryCutoff: 35)

    let decoded = try JSONDecoder().decode(ArmedRecord.self, from: JSONEncoder().encode(record))

    #expect(decoded == record)
}
