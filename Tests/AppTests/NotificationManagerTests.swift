import Testing

@testable import App

@MainActor @Test func shouldNotifyForPermissionRequest() {
    #expect(NotificationManager.shouldNotify(event: "PermissionRequest"))
}

@MainActor @Test func shouldNotifyForStop() {
    #expect(NotificationManager.shouldNotify(event: "Stop"))
}

@MainActor @Test func shouldNotifyForSessionEnd() {
    #expect(NotificationManager.shouldNotify(event: "SessionEnd"))
}

@MainActor @Test func shouldNotNotifyForSessionStart() {
    #expect(!NotificationManager.shouldNotify(event: "SessionStart"))
}

@MainActor @Test func shouldNotNotifyForUserPromptSubmit() {
    #expect(!NotificationManager.shouldNotify(event: "UserPromptSubmit"))
}

@MainActor @Test func shouldNotNotifyForNotification() {
    #expect(!NotificationManager.shouldNotify(event: "Notification"))
}
