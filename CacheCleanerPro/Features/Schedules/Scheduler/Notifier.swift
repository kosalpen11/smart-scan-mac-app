import Foundation
@preconcurrency import UserNotifications

// MARK: - Notifications

@MainActor
enum Notifier {
    nonisolated static let dueCategory = "RULE_DUE"
    nonisolated static let reviewAction = "REVIEW_AND_CLEAN"
    nonisolated static let skipAction = "SKIP_THIS_TIME"
    nonisolated static let ruleIDKey = "ruleID"

    static var center: UNUserNotificationCenter { .current() }

    static func configure() {
        let review = UNNotificationAction(identifier: reviewAction, title: "Review & Clean", options: [.foreground])
        let skip = UNNotificationAction(identifier: skipAction, title: "Skip This Time", options: [])
        let category = UNNotificationCategory(identifier: dueCategory, actions: [review, skip],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    static func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        default: return false
        }
    }

    static func postDue(_ rule: Rule, preview: CleanPreview) async {
        let content = UNMutableNotificationContent()
        content.title = rule.name
        content.body = dueBody(rule, preview: preview)
        content.sound = .default
        content.categoryIdentifier = dueCategory
        content.userInfo = [ruleIDKey: rule.id.uuidString]
        let request = UNNotificationRequest(identifier: "due-\(rule.id.uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }

    static func postResult(ruleName: String, result: RuleResult) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = result.succeeded ? "\(ruleName) finished" : "\(ruleName) didn't finish"
        if result.succeeded && result.bytesFreed > 0 {
            content.body = "Freed \(Format.bytes(result.bytesFreed)). \(result.message)"
        } else {
            content.body = result.message
        }
        let request = UNNotificationRequest(identifier: "result-\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func dueBody(_ rule: Rule, preview: CleanPreview) -> String {
        switch preview.content {
        case .items(let items):
            let summary = "\(Format.items(items.count)) (\(Format.bytes(preview.totalSize)))"
            switch rule.kind {
            case .trash:
                return rule.olderThanDays > 0
                    ? "\(summary) have been in the Trash for over \(rule.olderThanDays) days."
                    : "\(summary) are in the Trash."
            default:
                return "\(summary) in \(rule.folderURL.lastPathComponent) are ready to clean."
            }
        case .commandOutput:
            return "\(rule.preset.tool.displayName) has files to clean up."
        case .trashUnreadable:
            return "It's time to empty the Trash."
        }
    }
}
