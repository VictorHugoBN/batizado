import BatizadoCore
import Foundation
import UserNotifications
import os

@MainActor
protocol Notifying: AnyObject {
    /// Shows the system's permission prompt if the user was never asked; does nothing otherwise.
    func requestPermission()
    /// Posts only when notifications are already allowed, so it can never prompt by itself.
    func post(title: String, body: String)
    /// Like `post`, with the "Extend 30 min" action; a newer warning replaces the previous one.
    func postTimerWarning(title: String, body: String)
    /// Runs on the main actor when "Extend 30 min" is chosen, even with the app in the background.
    var onExtend: (@MainActor () -> Void)? { get set }
}

@MainActor
final class UserNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "notifications")
    private nonisolated static let timerCategory = "timer-warning"
    private nonisolated static let extendAction = "extend"

    private var center: UNUserNotificationCenter { .current() }
    var onExtend: (@MainActor () -> Void)?

    override init() {
        super.init()
        center.delegate = self
        // No .foreground option: the action runs in the background and the popover stays closed.
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.timerCategory,
                actions: [UNNotificationAction(identifier: Self.extendAction, title: "Extend 30 min")],
                intentIdentifiers: [])
        ])
        // Reading the settings never prompts; the line in the log shows whether the system knows the app.
        center.getNotificationSettings { [log] settings in
            log.notice("Notification permission: \(settings.authorizationStatus.name, privacy: .public)")
        }
    }

    func requestPermission() {
        center.getNotificationSettings { [log] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
                granted, error in
                if let error {
                    log.error("Notification permission request failed: \(error, privacy: .public)")
                } else {
                    log.notice("Notification permission \(granted ? "granted" : "denied", privacy: .public)")
                }
            }
        }
    }

    func post(title: String, body: String) {
        post(title: title, body: body, identifier: UUID().uuidString, category: nil)
    }

    func postTimerWarning(title: String, body: String) {
        post(title: title, body: body, identifier: Self.timerCategory, category: Self.timerCategory)
    }

    private func post(title: String, body: String, identifier: String, category: String?) {
        center.getNotificationSettings { [log] settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional else {
                log.notice(
                    "Not posting \"\(title, privacy: .public)\": permission is \(status.name, privacy: .public)"
                )
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let category { content.categoryIdentifier = category }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    log.error("Could not post a notification: \(error, privacy: .public)")
                } else {
                    log.notice("Posted \"\(title, privacy: .public)\"")
                }
            }
        }
    }

    // A menu bar app is often the active app while its popover is open; show the banner anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.extendAction else { return }
        await MainActor.run {
            log.notice("\"Extend 30 min\" chosen from the notification")
            onExtend?()
        }
    }
}

extension UNAuthorizationStatus {
    fileprivate var name: String {
        switch self {
        case .notDetermined: "not determined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown (\(rawValue))"
        }
    }
}
