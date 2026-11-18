import Foundation

// MARK: - Rule kind

enum RuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case folder, command, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: "Folder"
        case .command: "Tool"
        case .trash: "Empty Trash"
        }
    }
}

// MARK: - Rule

struct Rule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: RuleKind
    var folderPath: String = ""
    /// 0 = any age; otherwise 7, 30 or 90
    var olderThanDays: Int = 30
    var preset: CommandPreset = .dockerSystem
    var schedule = Schedule()
    var deletePermanently = false
    var requireAuth = true
    var isEnabled = true
    var createdAt = Date()
    var lastRun: Date?
    var lastNotified: Date?
    var lastResult: RuleResult?

    static let ageOptions = [0, 7, 30, 90]

    /// The date this rule is next due, or nil if it is manual or switched off.
    var nextRun: Date? {
        guard isEnabled else { return nil }
        return schedule.nextDate(after: lastRun ?? createdAt)
    }

    func isDue(now: Date = Date()) -> Bool {
        guard let next = nextRun else { return false }
        return next <= now
    }

    /// True once we have already notified for the current due date.
    var alreadyNotifiedForCurrentDue: Bool {
        guard let next = nextRun, let notified = lastNotified else { return false }
        return notified >= next
    }

    /// Trash items are always deleted for good.
    var removesPermanently: Bool { kind == .trash ? true : deletePermanently }

    var symbol: String {
        switch kind {
        case .folder: "folder"
        case .command: preset.symbol
        case .trash: "trash"
        }
    }

    var folderURL: URL { URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath) }

    static func newFolder() -> Rule {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        return Rule(name: "Clean Downloads", kind: .folder, folderPath: downloads, olderThanDays: 30)
    }

    static func newTrash() -> Rule {
        Rule(name: "Empty Trash", kind: .trash, olderThanDays: 30, deletePermanently: true)
    }

    static func newCommand(_ preset: CommandPreset) -> Rule {
        var rule = Rule(name: preset.title, kind: .command, olderThanDays: 0, preset: preset)
        rule.schedule.frequency = .monthly
        return rule
    }
}
