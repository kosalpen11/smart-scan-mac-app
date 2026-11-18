import AppKit
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.configure()
        // Don't wait for the permission prompt: if it's never answered, due rules
        // still run and open the review window directly.
        Scheduler.shared.start()
        Task { await Notifier.requestAuthorization() }
        Task { await AppStore.shared.refreshTrash() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let idString = response.notification.request.content.userInfo[Notifier.ruleIDKey] as? String
        guard let idString, let id = UUID(uuidString: idString) else { return }

        await MainActor.run {
            switch action {
            case Notifier.skipAction:
                AppStore.shared.skip(id)
            case Notifier.reviewAction, UNNotificationDefaultActionIdentifier:
                ConfirmWindowManager.shared.show(ruleID: id)
            default:
                break // Dismissed: stays due, and can be run from the app.
            }
        }
    }
}
