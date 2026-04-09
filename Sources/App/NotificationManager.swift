import AppKit
import Foundation
@preconcurrency import UserNotifications

/// Manages macOS system notifications for session state changes.
@MainActor
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var authorized = false

    /// User preference key — matches @AppStorage("notificationsEnabled") in SettingsView.
    static let enabledKey = "notificationsEnabled"

    /// Whether notifications are enabled. Defaults to true when unset.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Called when a notification is tapped — passes the sessionID back to the store.
    var onNotificationTapped: ((String) -> Void)?

    /// UNUserNotificationCenter requires a valid .app bundle — crashes when
    /// running via `swift run` from the .build directory. Guard all access.
    private var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self
        Task {
            do {
                authorized = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("[Runway] Notification authorization failed: \(error)")
            }
        }
    }

    /// Returns true if this event type should trigger a system notification.
    /// Note: `Stop` (turn complete, session idle) is intentionally excluded —
    /// it fires on every Claude turn and would be extremely noisy.
    static func shouldNotify(event: String) -> Bool {
        event == "PermissionRequest" || event == "SessionEnd"
    }

    /// Posts a local notification for a session event.
    func postSessionNotification(
        sessionID: String,
        sessionTitle: String,
        event: String
    ) {
        guard isEnabled, authorized, isBundled else { return }

        let content = UNMutableNotificationContent()
        content.userInfo = ["sessionID": sessionID]
        content.sound = .default

        switch event {
        case "PermissionRequest":
            content.title = "Permission Required"
            content.body = "\(sessionTitle) is waiting for your approval"
        case "SessionEnd":
            content.title = "Session Finished"
            content.body = "\(sessionTitle) has completed"
        default:
            return
        }

        let request = UNNotificationRequest(
            identifier: "\(sessionID)-\(event)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("[Runway] Failed to post notification: \(error)")
            }
        }
    }

    /// Updates the dock badge with the count of waiting sessions.
    /// Clears the badge when notifications are disabled.
    func updateDockBadge(waitingCount: Int) {
        if isEnabled, waitingCount > 0 {
            NSApp.dockTile.badgeLabel = "\(waitingCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    /// Removes delivered notifications for a specific session from the notification center.
    func clearDeliveredNotifications(forSessionID sessionID: String) {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let matching =
                notifications
                .filter { $0.request.content.userInfo["sessionID"] as? String == sessionID }
                .map(\.request.identifier)
            if !matching.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: matching)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification taps — navigate to the session.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        guard let sessionID else { return }
        await MainActor.run {
            onNotificationTapped?(sessionID)
        }
    }
}
