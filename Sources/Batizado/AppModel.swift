import AppKit
import BatizadoCore
import BatizadoSystem
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    /// Read from the login agent on disk, never remembered.
    private(set) var launchAtLogin = false

    private let assertions: any PowerAssertionHolding
    private let preferences: any PreferencesStoring
    private let sleepDisabled: any SleepDisabledSensing
    private let sleepSwitch: any SleepDisabledSwitching
    private let helperRule: any HelperRuleManaging
    private let guardian: any GuardianLinking
    private let screenLock: any ScreenLocking
    private let notifier: any Notifying
    private let loginItem: any LaunchAtLoginManaging
    // Held so its notification handler, which only weakly captures it, keeps firing.
    private let battery: any BatterySensing
    // Held because its notification registrations end when it is released.
    private let thermal: any ThermalSensing
    // Held for the same reason: their C callbacks point at them and stop only when they are released.
    private let lid: any LidSensing
    private let displays: any ExternalDisplaySensing
    private let now: () -> Date
    @ObservationIgnored private var timerCheck: (any DispatchSourceTimer)?
    @ObservationIgnored private var scheduledCheck: Instant?
    @ObservationIgnored private var clockObservers: [any NSObjectProtocol] = []
    private let timerLog = Logger(subsystem: AppInfo.bundleIdentifier, category: "timer")

    init(
        assertions: any PowerAssertionHolding = SystemPowerAssertions(),
        preferences: any PreferencesStoring = UserDefaultsPreferences(),
        sleepDisabled: any SleepDisabledSensing = SystemSleepDisabledSensor(),
        sleepSwitch: any SleepDisabledSwitching = SudoSleepDisabledSwitch(),
        helperRule: any HelperRuleManaging = SystemHelperRule(),
        guardian: any GuardianLinking = SystemGuardianLink(),
        lid: any LidSensing = SystemLidSensor(),
        displays: any ExternalDisplaySensing = SystemExternalDisplaySensor(),
        screenLock: any ScreenLocking = systemScreenLock(),
        battery: any BatterySensing = SystemBatterySensor(),
        thermal: any ThermalSensing = SystemThermalSensor(),
        notifier: any Notifying = UserNotifier(),
        loginItem: any LaunchAtLoginManaging = SystemLaunchAtLogin(),
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.assertions = assertions
        self.preferences = preferences
        self.sleepDisabled = sleepDisabled
        self.sleepSwitch = sleepSwitch
        self.helperRule = helperRule
        self.guardian = guardian
        self.screenLock = screenLock
        self.notifier = notifier
        self.loginItem = loginItem
        self.battery = battery
        self.thermal = thermal
        self.lid = lid
        self.displays = displays
        state = AppState(preferences: preferences.load())
        // Before launched, so a deadline that passed while the app was closed turns things off, not on.
        send(.clockTicked)
        send(.launched)
        notifier.onExtend = { [weak self] in self?.send(.extendTimer) }
        watchClock()
        send(.helperRuleChecked(installed: helperRule.isInstalled()))
        sleepDisabled.start { [weak self] in self?.send(.sleepDisabledChanged($0)) }
        helperRule.watch { [weak self] in self?.send(.helperRuleChecked(installed: $0)) }
        // Before the shutdown reason, so restoring Closed lid after a crash sees the battery and the heat.
        battery.start { [weak self] in self?.send(.batteryChanged($0)) }
        thermal.start { [weak self] in self?.send(.thermalChanged($0)) }
        guardian.installAgent()
        guardian.watchShutdowns { [weak self] in self?.send(.shutdownRecorded($0)) }
        // Last, so a waiting sticky reason, the battery and the heat are already known.
        send(.restore)
        if let notice = state.notice {
            Logger(subsystem: AppInfo.bundleIdentifier, category: "lifecycle").notice(
                "At launch Closed lid stayed off: \(String(describing: notice), privacy: .public)")
        }
        loginItem.repair()
        launchAtLogin = loginItem.isEnabled()
        #if DEBUG
            // Lets a test flip the toggle's own code path without clicking the popover.
            for on in [true, false] {
                DarwinNotification.observe(
                    AppInfo.bundleIdentifier + ".debug-launch-at-login-\(on ? "on" : "off")"
                ) {
                    [weak self] in self?.setLaunchAtLogin(on)
                }
            }
        #endif
        displays.start { [weak self] in self?.send(.externalDisplayChanged(active: $0)) }
        lid.start { [weak self] in self?.send(.lidChanged(closed: $0)) }
    }

    var launchAtLoginAvailable: Bool { loginItem.isAvailable }

    func setLaunchAtLogin(_ on: Bool) {
        loginItem.set(on)
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = loginItem.isEnabled()
    }

    func send(_ event: AppEvent) {
        let (next, effects) = reduce(state, event, at: Instant(now()))
        state = next
        effects.forEach(run)
        scheduleTimerCheck()
    }

    /// One wall-clock timer at the next warning or end, not a poll; it still fires after the Mac slept.
    private func scheduleTimerCheck() {
        let next = state.nextTimerCheck
        guard next != scheduledCheck else { return }
        timerCheck?.cancel()
        timerCheck = nil
        scheduledCheck = next
        guard let next else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        let seconds = next.secondsSince1970.rounded(.down)
        let wall = timespec(tv_sec: Int(seconds), tv_nsec: Int((next.secondsSince1970 - seconds) * 1e9))
        source.schedule(wallDeadline: DispatchWallTime(timespec: wall), leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduledCheck = nil
                self?.send(.clockTicked)
            }
        }
        source.resume()
        timerCheck = source
        timerLog.notice("Next timer check at \(next.date, privacy: .public)")
    }

    /// A wall-clock timer can be late after a sleep or a clock change; check the clock again at once.
    private func watchClock() {
        let check: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.clockTicked) }
        }
        clockObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: check),
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange, object: nil, queue: .main, using: check),
        ]
    }

    private func run(_ effect: Effect) {
        switch effect {
        case .hold(let assertion): assertions.hold(assertion)
        case .release(let assertion): assertions.release(assertion)
        case .save(let toggles): preferences.save(toggles)
        case .setSleepDisabled(let disabled):
            let ran = sleepSwitch.set(disabled)
            if ran { send(.sleepDisabledSwitched(disabled)) }
            // Read back at once: the change notification is not guaranteed to arrive.
            send(.sleepDisabledChanged(sleepDisabled.current()))
            if !ran { send(.helperRuleChecked(installed: helperRule.isInstalled())) }
            // powerd may apply the setting a moment after pmset exits; one late read clears a false warning.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.send(.sleepDisabledChanged(self.sleepDisabled.current()))
            }
        case .installHelperRule: send(.helperRuleInstallFinished(helperRule.install()))
        case .removeHelperRule: send(.helperRuleRemovalFinished(helperRule.remove()))
        case .arm(let cutoff): send(.armingFinished(succeeded: guardian.arm(batteryCutoff: cutoff)))
        case .updateArmed(let cutoff): _ = guardian.arm(batteryCutoff: cutoff)
        case .disarm: guardian.disarm()
        case .lockScreen: _ = screenLock.lock()
        case .requestNotificationPermission: notifier.requestPermission()
        case .notify(let reason):
            if reason == .timer { timerLog.notice("The timer ended; everything is off") }
            notifier.post(title: reason.notificationTitle, body: reason.explanation)
        case .warnTimer(let deadline):
            let time = deadline.date.formatted(date: .omitted, time: .shortened)
            timerLog.notice("Warning: the timer ends at \(deadline.date, privacy: .public)")
            notifier.postTimerWarning(
                title: "Turning off in 5 minutes",
                body: state.sleepDisabled == true
                    ? "Closed lid and Keep awake turn off at \(time)." : "Keep awake turns off at \(time).")
        }
    }
}

extension Instant {
    init(_ date: Date) {
        self.init(secondsSince1970: date.timeIntervalSince1970)
    }

    var date: Date { Date(timeIntervalSince1970: secondsSince1970) }
}
