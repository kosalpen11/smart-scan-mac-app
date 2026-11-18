import AppKit

// MARK: - Scheduler

@MainActor
final class Scheduler {
    static let shared = Scheduler()

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var isChecking = false
    private let store = ScheduleStore.shared

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await Scheduler.shared.check() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await Scheduler.shared.check() }
        }
        Task { await check() }
    }

    /// Finds due rules, runs their previews, and asks the user (never cleans by itself).
    func check(now: Date = Date()) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let due = store.rules.filter { $0.isDue(now: now) && !$0.alreadyNotifiedForCurrentDue }
        for rule in due {
            let preview: CleanPreview
            do {
                preview = try await store.preview(rule)
            } catch {
                // Try again at the next scheduled time rather than every 15 minutes.
                store.markDone(rule.id, message: error.localizedDescription, succeeded: false)
                continue
            }

            guard preview.hasWork else {
                store.markDone(rule.id, message: "Nothing to clean.")
                continue
            }

            store.update(rule.id) { $0.lastNotified = Date() }
            if await Notifier.isAuthorized() {
                await Notifier.postDue(rule, preview: preview)
            } else {
                ConfirmWindowManager.shared.show(ruleID: rule.id)
            }
        }
    }
}
