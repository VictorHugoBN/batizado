import Testing

@testable import BatizadoCore

@Test func turningKeepAwakeOnHoldsTheSystemAssertion() {
    let (state, effects) = reduce(running(), .setKeepAwake(true))

    #expect(state.keepAwake)
    #expect(effects.contains(.hold(.systemIdle)))
    #expect(!effects.contains(.hold(.displayIdle)))
}

@Test func turningKeepAwakeOffReleasesTheSystemAssertion() {
    let (state, effects) = reduce(running(keepAwake: true), .setKeepAwake(false))

    #expect(!state.keepAwake)
    #expect(effects.contains(.release(.systemIdle)))
}

@Test func keepDisplayOnHoldsTheDisplayAssertionWhileKeepAwakeIsOn() {
    let (state, effects) = reduce(running(keepAwake: true), .setKeepDisplayOn(true))

    #expect(state.keepDisplayOn)
    #expect(assertionEffects(effects) == [.hold(.displayIdle)])
}

@Test func keepDisplayOnIsRememberedButHoldsNothingWhileKeepAwakeIsOff() {
    let (state, effects) = reduce(running(), .setKeepDisplayOn(true))

    #expect(state.keepDisplayOn)
    #expect(assertionEffects(effects).isEmpty)
}

@Test func turningKeepAwakeOnWithKeepDisplayOnHoldsBothAssertions() {
    let (_, effects) = reduce(running(keepDisplayOn: true), .setKeepAwake(true))

    #expect(assertionEffects(effects) == [.hold(.systemIdle), .hold(.displayIdle)])
}

@Test func turningKeepAwakeOffReleasesTheDisplayAssertionToo() {
    let (state, effects) = reduce(running(keepAwake: true, keepDisplayOn: true), .setKeepAwake(false))

    #expect(state.keepDisplayOn)
    #expect(assertionEffects(effects) == [.release(.systemIdle), .release(.displayIdle)])
}

@Test func quittingReleasesEveryAssertionAndKeepsTheToggles() {
    let before = running(keepAwake: true, keepDisplayOn: true)

    let (state, effects) = reduce(before, .quit)

    #expect(effects.count == 2)
    #expect(assertionEffects(effects) == [.release(.systemIdle), .release(.displayIdle)])
    #expect(state.preferences == before.preferences)
}

@Test func changingAToggleSavesBothToggles() {
    let (_, effects) = reduce(running(keepDisplayOn: true), .setKeepAwake(true))

    #expect(effects.contains(.save(Preferences(keepAwake: true, keepDisplayOn: true))))
}

@Test func repeatingAToggleValueDoesNothing() {
    let (_, effects) = reduce(running(keepAwake: true), .setKeepAwake(true))

    #expect(effects.isEmpty)
}

@Test func launchingWithSavedTogglesHoldsTheirAssertions() {
    let saved = Preferences(keepAwake: true, keepDisplayOn: true)

    let (state, effects) = reduce(AppState(preferences: saved), .launched)

    #expect(state.preferences == saved)
    #expect(Set(effects) == [.hold(.systemIdle), .hold(.displayIdle)])
}

private func assertionEffects(_ effects: [Effect]) -> Set<Effect> {
    Set(
        effects.filter {
            switch $0 {
            case .hold, .release: true
            default: false
            }
        })
}
