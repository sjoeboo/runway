import AppKit
import Foundation
import UserNotifications

/// Manages macOS system notifications for session state changes.
@MainActor
public final class NotificationManager {
    private var authorized = false

    /// UNUserNotificationCenter requires a valid .app bundle — crashes when
    /// running via `swift run` from the .build directory. Guard all access.
    private var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorization() {
        guard isBundled else { return }
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
        guard authorized, isBundled else { return }

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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Runway] Failed to post notification: \(error)")
            }
        }
    }

    /// Updates the dock badge with the count of waiting sessions.
    func updateDockBadge(waitingCount: Int) {
        if waitingCount > 0 {
            NSApp.dockTile.badgeLabel = "\(waitingCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }
}
