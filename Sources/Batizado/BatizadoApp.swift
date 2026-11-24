import AppKit
import BatizadoCore
import BatizadoSystem
import SwiftUI
import os

@main
struct BatizadoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: delegate.model.state.menuBarIcon.symbolName) {
            MenuPanel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminationSignal: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `pkill` and logout send SIGTERM; route it through terminate so the revert below runs.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    // Runs the revert synchronously, so disablesleep is back to 0 before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        model.send(.quit)
        Logger(subsystem: AppInfo.bundleIdentifier, category: "lifecycle").info(
            "Quit; reverted what the app turned on")
    }
}

struct MenuPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppInfo.name)
                .font(.headline)
            ToggleRow(
                icon: "cup.and.saucer.fill",
                title: "Keep awake",
                isOn: Binding(
                    get: { model.state.keepAwake },
                    set: { model.send(.setKeepAwake($0)) }
                )
            )
            ToggleRow(
                icon: "laptopcomputer",
                title: "Closed lid",
                isOn: Binding(
                    get: { model.state.sleepDisabled },
                    set: { model.send(.setClosedLid($0)) }
                )
            )
            .help("Keeps the Mac awake with the lid closed. Shows the system's real SleepDisabled setting.")
            ClosedLidStatus(model: model)
            ToggleRow(
                icon: "display",
                title: "Keep display on",
                isOn: Binding(
                    get: { model.state.keepDisplayOn },
                    set: { model.send(.setKeepDisplayOn($0)) }
                )
            )
            .disabled(!model.state.keepAwake)
            ToggleRow(
                icon: "lock.laptopcomputer",
                title: "Lock on lid close",
                isOn: Binding(
                    get: { model.state.lockOnLidClose },
                    set: { model.send(.setLockOnLidClose($0)) }
                )
            )
            .help(
                "With Closed lid on, locks the screen when the lid closes and no external display is active.")
            BatteryCutoffRow(model: model)
            AutoTurnOffRow(model: model)
            ToggleRow(
                icon: "power",
                title: "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .disabled(!model.launchAtLoginAvailable)
            .help(
                model.launchAtLoginAvailable
                    ? "Opens Batizado when you log in, with a plain agent in ~/Library/LaunchAgents."
                    : "Move Batizado to a folder such as Applications and open it from there first.")
            Divider()
            Button("Remove helper rule") {
                model.send(.removeHelperRule)
            }
            .disabled(model.state.helperRule != .installed)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { model.refreshLaunchAtLogin() }
    }
}

private struct ClosedLidStatus: View {
    let model: AppModel

    var body: some View {
        let state = model.state
        if state.helperRule == .missing {
            warning("The helper rule was removed. Closed lid cannot change until you reinstall it.")
            Button("Reinstall helper rule") {
                model.send(.reinstallHelperRule)
            }
        }
        if state.closedLidDiverged {
            warning(
                state.closedLidRequest == true
                    ? "Closed lid is not active. The Mac will sleep when the lid closes."
                    : "Sleep is still disabled. The Mac will stay awake with the lid closed.")
        }
        switch state.notice {
        case .installFailed(let message): warning("Could not install the helper rule: \(message)")
        case .removeFailed(let message): warning("Could not remove the helper rule: \(message)")
        case .armFailed: warning("Closed lid stayed off: the guardian could not be armed.")
        case .batteryLow(let percent, let cutoff):
            warning(
                "Closed lid stayed off: the battery is at \(percent)%, at or below the \(cutoff)% cutoff. Plug in the charger or lower the cutoff."
            )
        case .overheated(let thermal):
            warning(
                "Closed lid stayed off: the Mac reports a \(thermal.rawValue) thermal state. Let it cool down and try again."
            )
        case .notRestored:
            warning(
                "Closed lid was left on but not turned back on: the helper rule is not installed. Turn Closed lid on to install it."
            )
        case nil: EmptyView()
        }
        if let reason = state.lastShutdown {
            warning(reason.explanation + (state.closedLidRequest == true ? " It was turned back on." : ""))
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BatteryCutoffRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.25percent")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text("Low battery cutoff")
            Spacer(minLength: 12)
            Picker(
                "Low battery cutoff",
                selection: Binding(
                    get: { model.state.batteryCutoff },
                    set: { model.send(.setBatteryCutoff($0)) }
                )
            ) {
                ForEach(BatteryCutoff.options(testMode: BuildMode.testMode), id: \.self) { cutoff in
                    Text(cutoff == BatteryCutoff.testValue ? "\(cutoff)% (test)" : "\(cutoff)%").tag(cutoff)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .help("On battery, turns Closed lid and Keep awake off at or below this level. Never on the charger.")
    }
}

private struct AutoTurnOffRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text("Auto turn off")
            Spacer(minLength: 12)
            Picker(
                "Auto turn off",
                selection: Binding(
                    get: { model.state.autoTurnOff },
                    set: { model.send(.setAutoTurnOff($0)) }
                )
            ) {
                ForEach(AutoTurnOff.options(testMode: BuildMode.testMode), id: \.self) { duration in
                    Text(duration.label).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .help("Turns Keep awake and Closed lid off after this long, with a warning five minutes before.")
        if let deadline = model.state.timerDeadline?.date {
            HStack(spacing: 10) {
                // Text(timerInterval:) redraws itself only while the popover is on screen.
                (Text("Turns off in ") + Text(timerInterval: Date.now...max(deadline, .now), countsDown: true))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Extend 30 min") {
                    model.send(.extendTimer)
                }
                .controlSize(.small)
            }
        }
    }
}

extension AutoTurnOff {
    fileprivate var label: String {
        switch self {
        case .never: "Never"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        case .eightHours: "8 hours"
        case .test: testLabel
        }
    }

    private var testLabel: String {
        #if DEBUG
            "5 min 20 s (timer test)"
        #else
            "Never"
        #endif
    }
}

extension ShutdownReason {
    var explanation: String {
        switch self {
        case .appDied: "Closed lid was turned off because Batizado stopped unexpectedly."
        case .reboot: "Closed lid was turned off because the Mac restarted with it on."
        case .battery:
            "Closed lid and Keep awake were turned off because the battery reached the low battery cutoff."
        case .thermal:
            "Closed lid and Keep awake were turned off because the Mac reported a serious or critical thermal state."
        case .timer: "Keep awake and Closed lid were turned off because the Auto turn off timer ran out."
        case .user, .quit: "Closed lid was turned off."
        }
    }
}

extension ShutdownReason {
    var notificationTitle: String {
        self == .timer ? "Auto turn off" : "Closed lid turned off"
    }
}

extension MenuBarIcon {
    fileprivate var symbolName: String {
        switch self {
        case .off: "cup.and.saucer"
        case .awake: "cup.and.saucer.fill"
        case .closedLid: "cup.and.heat.waves.fill"
        case .diverged: "exclamationmark.triangle.fill"
        }
    }
}
