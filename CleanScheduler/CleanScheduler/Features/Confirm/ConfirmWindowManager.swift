import AppKit
import SwiftUI

/// Shows the review window as a standalone NSWindow, so it works when only the menu bar item is running.
@MainActor
final class ConfirmWindowManager {
    static let shared = ConfirmWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var closeObservers: [UUID: NSObjectProtocol] = [:]

    func show(ruleID: UUID) {
        NSApp.activate()
        if let existing = windows[ruleID] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard AppStore.shared.rule(id: ruleID) != nil else { return }

        let view = ConfirmView(ruleID: ruleID) { [weak self] in self?.close(ruleID) }
            .environment(AppStore.shared)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Review cleanup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[ruleID] = window

        closeObservers[ruleID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in ConfirmWindowManager.shared.forget(ruleID) }
        }
    }

    func close(_ ruleID: UUID) {
        windows[ruleID]?.close()
        forget(ruleID)
    }

    private func forget(_ ruleID: UUID) {
        windows[ruleID] = nil
        if let observer = closeObservers.removeValue(forKey: ruleID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
