import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    // MARK: Persisted state

    var rules: [Rule] = [] {
        didSet { save(rules, key: Keys.rules) }
    }

    var history: [HistoryEntry] = [] {
        didSet { save(history, key: Keys.history) }
    }

    // MARK: Trash state

    enum TrashState {
        case loading
        case listed([CleanItem])
        /// Couldn't read ~/.Trash (no Full Disk Access).
        case unreadable
    }

    var trash: TrashState = .loading
    var trashBusy = false
    var trashMessage: String?

    var trashItems: [CleanItem] {
        if case .listed(let items) = trash { return items }
        return []
    }

    var trashSize: Int64 { trashItems.reduce(0) { $0 + $1.size } }

    // MARK: Settings

    var openAtLogin = LoginItem.isEnabled
    var loginItemMessage: String?

    private enum Keys {
        static let rules = "rules.v1"
        static let history = "history.v1"
    }

    private init() {
        rules = load([Rule].self, key: Keys.rules) ?? []
        history = load([HistoryEntry].self, key: Keys.history) ?? []
    }

    // MARK: Rules

    func save(_ rule: Rule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    func delete(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
    }

    func rule(id: UUID) -> Rule? { rules.first { $0.id == id } }

    func update(_ id: UUID, _ change: (inout Rule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[index])
    }

    /// The enabled rule that runs soonest.
    var nextScheduled: (rule: Rule, date: Date)? {
        rules.compactMap { rule in rule.nextRun.map { (rule, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: Running rules

    func preview(_ rule: Rule) async throws -> CleanPreview {
        try await Task.detached(priority: .userInitiated) { try RuleEngine.preview(rule) }.value
    }

    /// Cleans exactly what `preview` showed, then records and announces the result.
    func clean(_ rule: Rule, preview: CleanPreview) async -> RuleResult {
        var result: RuleResult
        do {
            if case .trashUnreadable = preview.content {
                try FinderTrash.emptyAll()
                result = RuleResult(date: Date(), succeeded: true, bytesFreed: 0, itemCount: 0,
                                    message: "Finder emptied the Trash.")
            } else {
                result = try await Task.detached(priority: .userInitiated) {
                    try RuleEngine.perform(rule, preview: preview)
                }.value
            }
        } catch {
            result = RuleResult(date: Date(), succeeded: false, bytesFreed: 0, itemCount: 0,
                                message: error.localizedDescription)
        }

        update(rule.id) {
            $0.lastRun = result.date
            $0.lastResult = result
        }
        if result.succeeded || result.itemCount > 0 {
            addHistory(name: rule.name, bytes: result.bytesFreed, items: result.itemCount)
        }
        await Notifier.postResult(ruleName: rule.name, result: result)
        if rule.kind == .trash { await refreshTrash() }
        return result
    }

    /// Marks the current due date as handled without cleaning.
    func skip(_ id: UUID) {
        update(id) {
            $0.lastRun = Date()
            $0.lastResult = RuleResult(date: Date(), succeeded: true, bytesFreed: 0, itemCount: 0,
                                       message: "Skipped this time.")
        }
    }

    func markDone(_ id: UUID, message: String, succeeded: Bool = true) {
        update(id) {
            $0.lastRun = Date()
            $0.lastResult = RuleResult(date: Date(), succeeded: succeeded, bytesFreed: 0, itemCount: 0, message: message)
        }
    }

    private func addHistory(name: String, bytes: Int64, items: Int) {
        history.insert(HistoryEntry(date: Date(), ruleName: name, bytesFreed: bytes, itemCount: items), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
    }

    func clearHistory() { history = [] }

    // MARK: Trash

    func refreshTrash() async {
        let listed = await Task.detached(priority: .utility) { () -> [CleanItem]? in
            try? FileCleaner.listTrash()
        }.value
        trash = listed.map { .listed($0) } ?? .unreadable
    }

    /// One-click Empty Trash. The caller has already shown a confirmation; this asks for
    /// Touch ID or the password, then deletes the items that were listed (or asks Finder).
    func emptyTrash() async {
        guard !trashBusy else { return }
        trashBusy = true
        trashMessage = nil
        defer { trashBusy = false }

        let snapshot = trash
        let reason: String
        switch snapshot {
        case .listed(let items): reason = "permanently delete \(Format.items(items.count)) from the Trash"
        default: reason = "empty the Trash"
        }

        switch await Auth.authenticate(reason: reason) {
        case .success: break
        case .cancelled: return
        case .failed(let message):
            trashMessage = message
            return
        }

        switch snapshot {
        case .listed(let items):
            let report = await Task.detached(priority: .userInitiated) {
                FileCleaner.remove(items, from: FileCleaner.trashURL, permanently: true)
            }.value
            let result = RuleEngine.result(from: report, verb: "Deleted")
            trashMessage = result.message
            if report.removedCount > 0 {
                addHistory(name: "Empty Trash", bytes: report.bytesFreed, items: report.removedCount)
            }
        case .unreadable, .loading:
            do {
                try FinderTrash.emptyAll()
                trashMessage = "Finder emptied the Trash."
                addHistory(name: "Empty Trash", bytes: 0, items: 0)
            } catch {
                trashMessage = error.localizedDescription
            }
        }
        await refreshTrash()
    }

    // MARK: Open at login

    func setOpenAtLogin(_ enabled: Bool) {
        loginItemMessage = LoginItem.set(enabled)
        openAtLogin = LoginItem.isEnabled
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
