import Foundation

/// Trash wording shared by the main window and the menu bar.
extension AppStore {
    var isTrashKnownEmpty: Bool {
        switch trash {
        case .loading: true
        case .listed(let items): items.isEmpty
        case .unreadable: false
        }
    }

    var trashSummary: String {
        switch trash {
        case .loading: "Checking…"
        case .listed(let items): items.isEmpty ? "Empty" : "\(Format.bytes(trashSize)) · \(Format.items(items.count))"
        case .unreadable: "Size unknown (needs Full Disk Access)"
        }
    }

    var emptyTrashQuestion: String {
        if case .listed(let items) = trash {
            return "Permanently delete \(Format.items(items.count)) (\(Format.bytes(trashSize)))?"
        }
        return "Empty the Trash?"
    }

    var emptyTrashWarning: String {
        if case .listed = trash {
            return "Items in the Trash will be deleted for good. This can't be undone."
        }
        return "Clean Scheduler can't read the Trash, so Finder will empty everything in it. This can't be undone."
    }
}
