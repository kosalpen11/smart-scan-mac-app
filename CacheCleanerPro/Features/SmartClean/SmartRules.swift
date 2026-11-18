import Foundation
import AppKit

/// An item Smart Clean suggests, with the reason it was picked.
struct SmartPick: Identifiable, Hashable, Sendable {
    let item: CleanupItem
    let category: CleanupCategory
    let reason: String
    /// Ticked when the Smart Clean sheet opens.
    let recommended: Bool

    var id: URL { item.url }
}

/// Decides which scanned items are junk, item by item, instead of taking whole categories.
enum SmartRules {
    nonisolated static let staleDays = 30
    nonisolated static let installerDays = 14

    nonisolated static func evaluate(_ results: [CleanupCategory: CategoryResult],
                                     runningBundleIDs: Set<String>,
                                     now: Date = .now) -> [SmartPick] {
        var picks: [SmartPick] = []
        for (category, result) in results {
            let items = result.items
            switch category {
            case .userCaches:
                picks += items.map { appCache($0, runningBundleIDs: runningBundleIDs) }

            case .simulatorCaches:
                picks += items.map { SmartPick($0, .simulatorCaches, "Rebuilt by the Simulator when needed") }

            case .derivedData:
                picks += items.compactMap { derivedData($0, now: now) }

            case .logs:
                picks += items.compactMap { item in
                    guard let days = age(latestModification(of: item), now), days >= staleDays else { return nil }
                    return SmartPick(item, .logs, "Not changed in \(days) days")
                }

            case .deviceSupport:
                picks += olderDeviceSupport(items)

            case .installers:
                picks += items.compactMap { item in
                    guard let days = age(item.modified, now), days >= installerDays else { return nil }
                    return SmartPick(item, .installers, "Downloaded \(days) days ago")
                }

            default:
                break
            }
        }
        return picks.sorted { $0.item.size > $1.item.size }
    }

    // MARK: Rules

    nonisolated static func appCache(_ item: CleanupItem, runningBundleIDs: Set<String>) -> SmartPick {
        let id = item.name
        if runningBundleIDs.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) {
            return SmartPick(item, .userCaches, "App is running", recommended: false)
        }
        // Only names shaped like com.company.app are bundle IDs; others (pip, Homebrew) aren't apps.
        // Helpers such as com.company.App.ShipIt belong to com.company.App, so check each parent ID too.
        let parts = id.split(separator: ".")
        if parts.count >= 3 {
            let candidates = (3...parts.count).map { parts.prefix($0).joined(separator: ".") }
            let installed = candidates.contains {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
            if !installed {
                return SmartPick(item, .userCaches, "No installed app matches \(id)")
            }
        }
        return SmartPick(item, .userCaches, "Rebuilt by the app when needed")
    }

    /// Xcode writes the project path and last-opened date into each DerivedData folder's info.plist.
    nonisolated static func derivedData(_ item: CleanupItem, now: Date) -> SmartPick? {
        let plistURL = item.url.appendingPathComponent("info.plist")
        let plist = (try? Data(contentsOf: plistURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }

        if let workspace = plist?["WorkspacePath"] as? String,
           !FileManager.default.fileExists(atPath: workspace) {
            return SmartPick(item, .derivedData, "Project folder is gone")
        }
        let lastUsed = plist?["LastAccessedDate"] as? Date ?? latestModification(of: item)
        if let days = age(lastUsed, now), days >= staleDays {
            return SmartPick(item, .derivedData, "Not opened in Xcode for \(days) days")
        }
        return nil
    }

    /// Keeps the newest version in each Device Support folder and suggests the older ones.
    nonisolated static func olderDeviceSupport(_ items: [CleanupItem]) -> [SmartPick] {
        var picks: [SmartPick] = []
        let byFolder = Dictionary(grouping: items) { $0.url.deletingLastPathComponent() }

        for (folder, group) in byFolder {
            let versioned = group.compactMap { item in version(in: item.name).map { (item, $0) } }
            guard let newest = versioned.map(\.1).max(by: { $0.lexicographicallyPrecedes($1) }) else { continue }

            // "iOS DeviceSupport" → "iOS"
            let platform = folder.lastPathComponent.split(separator: " ").first.map(String.init) ?? ""
            let newestText = newest.map(String.init).joined(separator: ".")
            for (item, v) in versioned where v.lexicographicallyPrecedes(newest) {
                picks.append(SmartPick(item, .deviceSupport, "Older than \(platform) \(newestText), the newest here"))
            }
        }
        return picks
    }

    // MARK: Helpers

    /// The first dotted number in a name, e.g. "iPhone15,2 17.5 (21F79)" → [17, 5].
    nonisolated static func version(in name: String) -> [Int]? {
        for token in name.split(separator: " ") {
            let parts = token.split(separator: ".").map { Int($0) }
            if parts.count >= 2, !parts.contains(nil) { return parts.compactMap { $0 } }
        }
        return nil
    }

    /// A folder's own date only changes when direct children are added or removed,
    /// so use the newest file anywhere inside it.
    nonisolated static func latestModification(of item: CleanupItem) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: item.url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return item.modified }

        var latest = item.modified
        while let file = enumerator.nextObject() as? URL {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date > (latest ?? .distantPast) {
                latest = date
            }
        }
        return latest
    }

    nonisolated static func age(_ date: Date?, _ now: Date) -> Int? {
        guard let date else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: now).day
    }
}

private extension SmartPick {
    nonisolated init(_ item: CleanupItem, _ category: CleanupCategory, _ reason: String, recommended: Bool = true) {
        self.init(item: item, category: category, reason: reason, recommended: recommended)
    }
}
