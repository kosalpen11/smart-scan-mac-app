import Foundation

// MARK: - Preview

struct CleanItem: Identifiable, Hashable, Sendable {
    var url: URL
    var size: Int64
    var date: Date?
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct CleanPreview: Sendable {
    enum Content: Sendable {
        case items([CleanItem])
        case commandOutput(String)
        /// The Trash couldn't be listed; only Finder's "empty everything" is possible.
        case trashUnreadable
    }

    var content: Content
    var hasWork: Bool
    var permanent: Bool

    var items: [CleanItem] {
        if case .items(let items) = content { return items }
        return []
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}
