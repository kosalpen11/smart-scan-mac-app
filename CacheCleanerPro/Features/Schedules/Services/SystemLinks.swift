import AppKit

enum SystemLinks {
    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openTrash() {
        NSWorkspace.shared.open(FileCleaner.trashURL)
    }
}
