import BatizadoCore
import IOKit.pwr_mgt
import os

@MainActor
protocol PowerAssertionHolding {
    func hold(_ assertion: PowerAssertion)
    func release(_ assertion: PowerAssertion)
}

@MainActor
final class SystemPowerAssertions: PowerAssertionHolding {
    private var held: [PowerAssertion: IOPMAssertionID] = [:]
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "power")

    func hold(_ assertion: PowerAssertion) {
        guard held[assertion] == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            assertion.type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "\(AppInfo.name): \(assertion.reason)" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            log.error("Could not hold \(assertion.type, privacy: .public): \(result)")
            return
        }
        held[assertion] = id
    }

    func release(_ assertion: PowerAssertion) {
        guard let id = held.removeValue(forKey: assertion) else { return }
        IOPMAssertionRelease(id)
    }
}

extension PowerAssertion {
    fileprivate var type: String {
        switch self {
        case .systemIdle: kIOPMAssertionTypePreventUserIdleSystemSleep
        case .displayIdle: kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
    }

    fileprivate var reason: String {
        switch self {
        case .systemIdle: "Keep awake"
        case .displayIdle: "Keep display on"
        }
    }
}
