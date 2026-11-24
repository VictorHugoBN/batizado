import AppKit
import BatizadoCore
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

extension ShutdownReason {
    fileprivate var explanation: String {
        switch self {
        case .appDied: "Closed lid was turned off because Batizado stopped unexpectedly."
        case .reboot: "Closed lid was turned off because the Mac restarted with it on."
        case .battery: "Closed lid was turned off because the battery ran low."
        case .thermal: "Closed lid was turned off because the Mac got too hot."
        case .timer: "Closed lid was turned off because the timer ran out."
        case .user, .quit: "Closed lid was turned off."
        }
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
