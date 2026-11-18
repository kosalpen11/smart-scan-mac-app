import Foundation

/// File work: validating folders, listing items, measuring size and removing.
/// Everything here is nonisolated and meant to run off the main actor.
enum FileCleaner {
    nonisolated static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
    }

    nonisolated static var trashURL: URL { home.appendingPathComponent(".Trash", isDirectory: true) }

    // MARK: Paths

    /// Resolves symlinks in the parent only, so a symlink item stays the link (never its target).
    nonisolated static func resolved(_ url: URL) -> URL {
        let standard = url.standardizedFileURL
        let parent = standard.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(standard.lastPathComponent)
    }

    /// Path components below the home folder, or nil if the path is not inside it.
    nonisolated static func componentsInsideHome(_ url: URL) -> [String]? {
        let homePath = home.path
        let path = url.path
        guard path.hasPrefix(homePath + "/") else { return nil }
        let rest = path.dropFirst(homePath.count + 1)
        let parts = rest.split(separator: "/").map(String.init)
        if parts.isEmpty || parts.contains("..") || parts.contains(".") { return nil }
        return parts
    }

    // MARK: Folder validation

    private nonisolated static let blockedExact: [String] = [
        "Library", "Documents", "Desktop", "Pictures", "Music", "Movies", "Applications",
        "Library/Application Support", "Library/Group Containers",
    ]

    /// Blocked, including everything inside them.
    private nonisolated static let blockedTree: [String] = [
        ".ssh", ".gnupg", "Library/Keychains", "Library/Containers",
    ]

    private nonisolated static let dockerPaths: [String] = [
        ".docker",
        "Library/Containers/com.docker.docker",
        "Library/Group Containers/group.com.docker",
    ]

    /// Returns a message describing the problem, or nil if the folder can be used by a rule.
    nonisolated static func validateFolder(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Choose a folder to clean." }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "This folder doesn't exist. Choose a folder that does."
        }
        guard isDirectory.boolValue else { return "This is a file, not a folder. Choose a folder." }

        if url.path == home.path {
            return "You can't clean your whole home folder. Choose a folder inside it, like Downloads."
        }
        guard let parts = componentsInsideHome(url) else {
            return "Choose a folder inside your home folder."
        }
        let relative = parts.joined(separator: "/")

        func isInside(_ base: String) -> Bool { relative == base || relative.hasPrefix(base + "/") }

        if dockerPaths.contains(where: isInside) {
            return "This is Docker's data folder. Use a Docker Cleanup rule instead, so Docker removes its own files safely."
        }
        if isInside(".Trash") {
            return "This is the Trash. Use an Empty Trash rule instead."
        }
        if blockedTree.contains(where: isInside) || blockedExact.contains(relative) {
            return "“\(url.lastPathComponent)” holds important files and can't be cleaned. Choose a more specific folder."
        }
        return nil
    }

    // MARK: Listing

    /// Direct children of a folder that are older than `olderThanDays` (by modification date), with sizes.
    nonisolated static func listFolder(_ folder: URL, olderThanDays: Int, now: Date = Date()) throws -> [CleanItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let cutoff = cutoffDate(olderThanDays, now: now)
        return children.compactMap { child in
            let date = (try? child.resourceValues(forKeys: Set(keys)))?.contentModificationDate
            if let cutoff, let date, date > cutoff { return nil }
            return CleanItem(url: child, size: sizeOnDisk(child), date: date)
        }
        .sorted { $0.size > $1.size }
    }

    /// Children of ~/.Trash, dated by when they were moved to the Trash. Throws without Full Disk Access.
    nonisolated static func listTrash(olderThanDays: Int = 0, now: Date = Date()) throws -> [CleanItem] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
        let children = try FileManager.default.contentsOfDirectory(
            at: trashURL, includingPropertiesForKeys: keys, options: [])
        let cutoff = cutoffDate(olderThanDays, now: now)
        return children.compactMap { child in
            if child.lastPathComponent == ".DS_Store" { return nil }
            let values = try? child.resourceValues(forKeys: Set(keys))
            let date = values?.addedToDirectoryDate ?? values?.contentModificationDate
            if let cutoff, let date, date > cutoff { return nil }
            return CleanItem(url: child, size: sizeOnDisk(child), date: date)
        }
        .sorted { $0.size > $1.size }
    }

    private nonisolated static func cutoffDate(_ days: Int, now: Date) -> Date? {
        days > 0 ? Calendar.current.date(byAdding: .day, value: -days, to: now) : nil
    }

    /// Allocated size on disk. Does not follow symlinks.
    nonisolated static func sizeOnDisk(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        let own = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard values.isDirectory == true, values.isSymbolicLink != true else { return own }

        var total = own
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let child = enumerator?.nextObject() as? URL {
            let v = try? child.resourceValues(forKeys: keys)
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: Removal

    struct RemovalReport: Sendable {
        var removedCount = 0
        var bytesFreed: Int64 = 0
        var failures: [String] = []
    }

    /// Removes exactly the given items. Each must sit directly inside `parent`, be inside the home
    /// folder, and not be a top-level home folder. The removal itself goes through the app's
    /// `Cleaner.run`, so its protected-folder and Never Clean checks apply too.
    nonisolated static func remove(_ items: [CleanItem], from parent: URL, permanently: Bool,
                                   excludedPaths: [String]) -> RemovalReport {
        var report = RemovalReport()
        let fm = FileManager.default
        let expectedParent = parent.standardizedFileURL.resolvingSymlinksInPath().path

        var jobs: [CleanJob] = []
        var names: [URL: String] = [:]
        for item in items {
            let target = resolved(item.url)
            guard let parts = componentsInsideHome(target) else {
                report.failures.append("\(item.name): outside your home folder, skipped.")
                continue
            }
            guard parts.count >= 2 else {
                report.failures.append("\(item.name): a top-level home folder, skipped.")
                continue
            }
            guard target.deletingLastPathComponent().path == expectedParent else {
                report.failures.append("\(item.name): not in the cleaned folder, skipped.")
                continue
            }
            // Must still exist (as itself, a link counts) at the time of removal.
            guard (try? target.checkResourceIsReachable()) == true
                || (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil else {
                continue
            }
            jobs.append(CleanJob(url: target, size: item.size, permanent: permanently))
            names[target] = item.name
        }

        let cleaned = Cleaner.run(jobs, excludedPaths: excludedPaths)
        report.removedCount = cleaned.removed.count
        report.bytesFreed = cleaned.freed
        for url in cleaned.failed {
            report.failures.append("\(names[url] ?? url.lastPathComponent): in use, protected or set to Never Clean, skipped.")
        }
        return report
    }

    /// True if `url` is a Never Clean path, inside one, or holds one.
    nonisolated static func touchesExclusion(_ url: URL, _ excludedPaths: [String]) -> Bool {
        let path = url.standardizedFileURL.path
        return excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
    }
}
