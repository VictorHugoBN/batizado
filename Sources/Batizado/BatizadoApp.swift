import AppKit
import BatizadoCore
import BatizadoSystem
import SwiftUI
import os

@main
enum Launch {
    @MainActor static func main() {
        #if DEBUG
            // Debug only: draws the popover and the icons to PNGs and exits before any sensor starts.
            if let directory = PanelSnapshots.requestedDirectory() {
                PanelSnapshots.write(to: directory)
                exit(0)
            }
        #endif
        BatizadoApp.main()
    }
}

struct BatizadoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: delegate.model)
        } label: {
            let icon = delegate.model.state.menuBarIcon
            Image(nsImage: icon.image)
                .accessibilityLabel(icon.accessibilityLabel)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(Palette.accent)
                Text(AppInfo.name)
                    .font(.headline)
            }
            .padding(.bottom, 2)
            ToggleRow(
                icon: "cup.and.heat.waves",
                title: "Keep awake",
                isOn: Binding(
                    get: { model.state.keepAwake },
                    set: { model.send(.setKeepAwake($0)) }
                )
            )
            .help("Keeps the Mac from sleeping while the lid is open.")
            ToggleRow(
                icon: "laptopcomputer",
                title: "Closed lid",
                isOn: Binding(
                    get: { model.state.sleepDisabled == true },
                    set: { model.send(.setClosedLid($0)) }
                )
            )
            .help(
                "Keeps the Mac awake with the lid closed. The switch shows the system's real sleep setting.")
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
            .help("Keeps the display from sleeping while Keep awake is on.")
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
                    ? "Opens Batizado when you log in, using a login agent in ~/Library/LaunchAgents."
                    : "Move Batizado to the Applications folder and open it from there first.")
            Divider()
            ActionRow(icon: "heart", title: "Sponsor", opensLink: true) {
                if let url = URL(string: AppInfo.sponsorURL) { NSWorkspace.shared.open(url) }
            }
            .help("Opens the GitHub Sponsors page for Batizado in your browser.")
            ActionRow(icon: "trash", title: "Remove helper rule") {
                model.send(.removeHelperRule)
            }
            .disabled(model.state.helperRule != .installed)
            .help(
                "Turns Closed lid off and removes the helper rule. macOS asks for an administrator password.")
            ActionRow(icon: "xmark.circle", title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 300)
        .tint(Palette.accent)
        .onAppear { model.refreshLaunchAtLogin() }
    }
}

private struct ClosedLidStatus: View {
    let model: AppModel

    var body: some View {
        let state = model.state
        if state.helperRule == .missing {
            PanelNote(text: "The helper rule was removed. Closed lid cannot change until you reinstall it.")
            Button("Reinstall helper rule") {
                model.send(.reinstallHelperRule)
            }
            .controlSize(.small)
        }
        if state.sleepDisabled == nil {
            PanelNote(
                text:
                    "Batizado cannot read the system's sleep setting, so it cannot tell whether Closed lid is active."
            )
        } else if state.closedLidDiverged {
            PanelNote(
                text: state.closedLidRequest == true
                    ? "Closed lid is not active. The Mac will sleep when the lid closes."
                    : "Closed lid is still active. The Mac will stay awake with the lid closed.")
        }
        if let text = state.notice?.text {
            PanelNote(text: text)
        }
        if let reason = state.lastShutdown {
            PanelNote(
                text: reason.explanation + (state.closedLidRequest == true ? " It was turned back on." : ""),
                isWarning: false)
        }
    }
}

extension Notice {
    fileprivate var text: String {
        switch self {
        case .installFailed(let message): "Could not install the helper rule: \(message)"
        case .removeFailed(let message): "Could not remove the helper rule: \(message)"
        case .armFailed:
            "Closed lid stayed off: Batizado could not set up the guardian that turns it off if the app stops."
        case .batteryLow(let percent, let cutoff):
            "Closed lid stayed off: the battery is at \(percent)%, at or below the \(cutoff)% Low battery cutoff. Plug in the charger or lower the cutoff."
        case .overheated(let thermal):
            "Closed lid stayed off: the Mac is too hot (\(thermal.rawValue) thermal state). Let it cool down and try again."
        case .notRestored:
            "Closed lid was on when Batizado quit, but it was not turned back on because the helper rule is not installed. Turn Closed lid on to install it."
        }
    }
}

private struct BatteryCutoffRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Label("Low battery cutoff", systemImage: "battery.25percent")
                .labelStyle(RowLabelStyle())
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
            .frame(width: 88)
        }
        .help("On battery, turns Closed lid and Keep awake off at or below this level. Never while charging.")
    }
}

private struct AutoTurnOffRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Label("Auto turn off", systemImage: "timer")
                .labelStyle(RowLabelStyle())
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
            .frame(width: 88)
        }
        .help("Turns Keep awake and Closed lid off after this long, with a warning five minutes before.")
        if let deadline = model.state.timerDeadline?.date {
            HStack(spacing: 10) {
                // Text(timerInterval:) redraws itself only while the popover is on screen.
                (Text("Turns off in ") + Text(timerInterval: Date.now...max(deadline, .now), countsDown: true))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
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
            "Closed lid and Keep awake were turned off because the battery reached the Low battery cutoff."
        case .thermal:
            "Closed lid and Keep awake were turned off because the Mac got too hot (serious or critical thermal state)."
        case .timer: "The Auto turn off timer ran out, so Keep awake and Closed lid are now off."
        case .user, .quit: "Closed lid was turned off."
        }
    }
}

extension ShutdownReason {
    var notificationTitle: String {
        self == .timer ? "Auto turn off" : "Closed lid turned off"
    }
}
