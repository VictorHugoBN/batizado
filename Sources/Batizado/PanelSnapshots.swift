#if DEBUG
    import AppKit
    import BatizadoCore
    import SwiftUI

    /// Debug builds only: `Batizado --write-snapshots <dir>` draws the popover in a few states, light and
    /// dark, plus the four menu bar icons, to PNG files. Every adapter is a stand-in, so nothing on the
    /// system is read or changed.
    @MainActor
    enum PanelSnapshots {
        static func requestedDirectory() -> URL? {
            let arguments = CommandLine.arguments
            guard let flag = arguments.firstIndex(of: "--write-snapshots"), flag + 1 < arguments.count else {
                return nil
            }
            return URL(filePath: arguments[flag + 1], directoryHint: .isDirectory)
        }

        static func write(to directory: URL) {
            _ = NSApplication.shared
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, model) in scenarios() {
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    save(
                        panel(model, appearance: appearance),
                        to: directory.appending(path: "\(name)-\(suffix).png"))
                }
            }
            save(menuBarStrip(), to: directory.appending(path: "menubar.png"))
        }

        private static func scenarios() -> [(String, AppModel)] {
            var result: [(String, AppModel)] = []

            let off = Stand()
            result.append(("1-off", off.model()))

            let awake = Stand()
            awake.loginItem.enabled = true
            let awakeModel = awake.model()
            awakeModel.send(.setKeepAwake(true))
            awakeModel.send(.setKeepDisplayOn(true))
            awakeModel.send(.setAutoTurnOff(.twoHours))
            result.append(("2-awake", awakeModel))

            let closedLid = Stand(ruleInstalled: true)
            let closedLidModel = closedLid.model()
            closedLidModel.send(.setClosedLid(true))
            result.append(("3-closed-lid", closedLidModel))

            let diverged = Stand(ruleInstalled: true)
            diverged.sleepSwitch.applies = false
            let divergedModel = diverged.model()
            divergedModel.send(.setClosedLid(true))
            result.append(("4-diverged", divergedModel))

            let reverted = Stand(ruleInstalled: true)
            let revertedModel = reverted.model()
            revertedModel.send(.setClosedLid(true))
            reverted.sleepDisabled.value = false
            revertedModel.send(.shutdownRecorded(.battery))
            revertedModel.send(.batteryChanged(BatteryReading(onAC: false, percent: 12)))
            revertedModel.send(.setClosedLid(true))
            result.append(("5-reverted-and-refused", revertedModel))

            let missing = Stand(ruleInstalled: true)
            missing.loginItem.isAvailable = false
            let missingModel = missing.model()
            missingModel.send(.setKeepAwake(true))
            missingModel.send(.helperRuleChecked(installed: false))
            missingModel.send(.shutdownRecorded(.appDied))
            result.append(("6-rule-missing", missingModel))

            return result
        }

        private static func panel(_ model: AppModel, appearance: NSAppearance.Name) -> NSBitmapImageRep {
            let root = MenuPanel(model: model)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: 280, height: 600),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.setFrameSize(host.fittingSize)
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            host.display()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            return rep
        }

        private static func menuBarStrip() -> NSBitmapImageRep {
            let icons: [MenuBarIcon] = [.off, .awake, .closedLid, .diverged]
            let bars: [(NSColor, NSColor)] = [
                (NSColor(white: 0.94, alpha: 1), .black), (NSColor(white: 0.13, alpha: 1), .white),
            ]
            let scales: [CGFloat] = [1, 2]
            let cell = NSSize(width: 30, height: 24)
            let size = NSSize(
                width: cell.width * CGFloat(icons.count) * CGFloat(scales.count) + 10,
                height: cell.height * CGFloat(bars.count))
            let pixels = 2.0
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * pixels),
                pixelsHigh: Int(size.height * pixels),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            for (row, (bar, ink)) in bars.enumerated() {
                let y = size.height - CGFloat(row + 1) * cell.height
                bar.setFill()
                NSRect(x: 0, y: y, width: size.width, height: cell.height).fill()
                for (group, scale) in scales.enumerated() {
                    for (column, icon) in icons.enumerated() {
                        let x =
                            CGFloat(group) * (cell.width * CGFloat(icons.count) + 10) + CGFloat(column)
                            * cell.width
                        let tinted = tint(icon.image, ink, pixelScale: scale)
                        tinted.draw(in: NSRect(x: x + 4, y: y + 3, width: 22, height: 18))
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }

        /// The menu bar draws templates in one color; `pixelScale` 1 shows a non-Retina display.
        private static func tint(_ image: NSImage, _ color: NSColor, pixelScale: CGFloat) -> NSImage {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(22 * pixelScale), pixelsHigh: Int(18 * pixelScale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: 22, height: 18)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let bounds = NSRect(x: 0, y: 0, width: 22, height: 18)
            image.draw(in: bounds)
            color.set()
            bounds.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            let result = NSImage(size: bounds.size)
            result.addRepresentation(rep)
            return result
        }

        private static func save(_ rep: NSBitmapImageRep, to url: URL) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    /// Stand-ins for every system adapter, so a snapshot model reaches real states through the real reducer.
    @MainActor
    private final class Stand {
        let sleepDisabled = StandSleepDisabled()
        let sleepSwitch: StandSwitch
        let rule: StandRule
        let loginItem = StandLoginItem()

        init(ruleInstalled: Bool = false) {
            sleepSwitch = StandSwitch(sensor: sleepDisabled)
            rule = StandRule(installed: ruleInstalled)
        }

        func model() -> AppModel {
            AppModel(
                assertions: StandNoop(), preferences: StandNoop(), sleepDisabled: sleepDisabled,
                sleepSwitch: sleepSwitch, helperRule: rule, guardian: StandNoop(), lid: StandBool(),
                displays: StandBool(), screenLock: StandNoop(), battery: StandNoop(), thermal: StandNoop(),
                notifier: StandNotifier(), loginItem: loginItem)
        }
    }

    @MainActor
    private final class StandSleepDisabled: SleepDisabledSensing {
        var value: Bool? = false
        func start(onChange: @escaping @MainActor (Bool?) -> Void) { onChange(value) }
        func current() -> Bool? { value }
    }

    @MainActor
    private final class StandSwitch: SleepDisabledSwitching {
        let sensor: StandSleepDisabled
        var applies = true
        init(sensor: StandSleepDisabled) { self.sensor = sensor }
        func set(_ disabled: Bool) -> Bool {
            if applies { sensor.value = disabled }
            return true
        }
    }

    @MainActor
    private final class StandRule: HelperRuleManaging {
        var installed: Bool
        init(installed: Bool) { self.installed = installed }
        func isInstalled() -> Bool { installed }
        func install() -> AdministratorOutcome { .cancelled }
        func remove() -> AdministratorOutcome { .cancelled }
        func watch(onChange: @escaping @MainActor (Bool) -> Void) {}
    }

    @MainActor
    private final class StandLoginItem: LaunchAtLoginManaging {
        var isAvailable = true
        var enabled = false
        func isEnabled() -> Bool { enabled }
        func repair() {}
        func set(_ on: Bool) { enabled = on }
    }

    @MainActor
    private final class StandBool: LidSensing, ExternalDisplaySensing {
        func start(onChange: @escaping @MainActor (Bool) -> Void) { onChange(false) }
    }

    @MainActor
    private final class StandNotifier: Notifying {
        var onExtend: (@MainActor () -> Void)?
        func requestPermission() {}
        func post(title: String, body: String) {}
        func postTimerWarning(title: String, body: String) {}
    }

    @MainActor
    private struct StandNoop: PowerAssertionHolding, PreferencesStoring, GuardianLinking, ScreenLocking,
        BatterySensing, ThermalSensing
    {
        func hold(_ assertion: PowerAssertion) {}
        func release(_ assertion: PowerAssertion) {}
        func load() -> Preferences { Preferences() }
        func save(_ preferences: Preferences) {}
        func arm(batteryCutoff: Int) -> Bool { true }
        func disarm() {}
        func watchShutdowns(onRecorded: @escaping @MainActor (ShutdownReason) -> Void) {}
        func installAgent() {}
        func lock() -> Bool { true }
        func start(onChange: @escaping @MainActor (BatteryReading?) -> Void) {
            onChange(BatteryReading(onAC: true, percent: 80))
        }
        func start(onChange: @escaping @MainActor (ThermalState) -> Void) { onChange(.nominal) }
    }
#endif
