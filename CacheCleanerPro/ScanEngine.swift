import Foundation

struct ScanOptions: Sendable {
    var includeAppleCaches: Bool
    var largeFileThreshold: Int64
    var excludedPaths: [String]
    var ownBundleID: String
}

// MARK: - Scanning

enum ScanEngine {
    nonisolated static func scan(_ category: CleanupCategory, options: ScanOptions) -> CategoryResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [CleanupItem] = []
        var denied = false

        for relative in category.roots {
            let root = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: root.path) else { continue }

            switch category.scanMode {
            case .wholeRoot:
                items += cleanableItems(at: root, options)

            case .children:
                do {
                    let children = try fm.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )
                    for child in children {
                        if let exts = category.allowedExtensions,
                           !exts.contains(child.pathExtension.lowercased()) { continue }
                        if child.lastPathComponent == options.ownBundleID { continue }
                        if category == .userCaches, !options.includeAppleCaches,
                           child.lastPathComponent.hasPrefix("com.apple.") { continue }
                        items += cleanableItems(at: child, options)
                    }
                } catch {
                    denied = true
                }

            case .largeFiles:
                items += findLargeFiles(in: root, options: options)
            }
        }

        items.sort { $0.size > $1.size }
        return CategoryResult(category: category, items: items, accessDenied: denied && items.isEmpty)
    }

    /// The item at `url` as one row, or, when an excluded path sits inside it,
    /// the parts around that path, so cleaning never removes something the user kept.
    nonisolated static func cleanableItems(at url: URL, _ options: ScanOptions) -> [CleanupItem] {
        if isExcluded(url, options) { return [] }

        if containsExcluded(url, options) {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return children.flatMap { cleanableItems(at: $0, options) }
        }

        let size = size(of: url)
        return size > 0 ? [CleanupItem(url: url, size: size, modified: modified(url))] : []
    }

    nonisolated static func findLargeFiles(in root: URL, options: ScanOptions) -> [CleanupItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey,
                                      .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [CleanupItem] = []
        while let file = enumerator.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isPackage != true,
                  values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? 0)
            guard size >= options.largeFileThreshold else { continue }
            // Installers already have their own category.
            if CleanupCategory.installerExtensions.contains(file.pathExtension.lowercased()) { continue }
            if isExcluded(file, options) { continue }

            found.append(CleanupItem(url: file, size: size, modified: values.contentModificationDate))
        }
        return found
    }

    /// Size on disk of a file or a whole folder.
    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        )
        while let file = enumerator?.nextObject() as? URL {
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    nonisolated static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    nonisolated static func isExcluded(_ url: URL, _ options: ScanOptions) -> Bool {
        let path = url.path
        return options.excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    nonisolated static func containsExcluded(_ url: URL, _ options: ScanOptions) -> Bool {
        let prefix = url.path + "/"
        return options.excludedPaths.contains { $0.hasPrefix(prefix) }
    }
}

// MARK: - Cleaning

struct CleanJob: Sendable {
    let url: URL
    let size: Int64
    let permanent: Bool
}

struct CleanReport: Sendable {
    var removed: Set<URL> = []
    var freed: Int64 = 0
    var failed: [URL] = []
}

enum Cleaner {
    /// Top-level folders that must never be removed themselves.
    nonisolated private static let protectedNames: Set<String> = [
        "Library", "Documents", "Desktop", "Downloads", "Movies",
        "Pictures", "Music", "Applications", "Public", ".Trash"
    ]

    nonisolated static func run(_ jobs: [CleanJob], excludedPaths: [String]) -> CleanReport {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL
        var report = CleanReport()

        for job in jobs {
            let url = job.url.standardizedFileURL

            // Safety net: only touch things inside the home folder,
            // and never a top-level folder like ~/Documents.
            let isInsideHome = url.path.hasPrefix(home.path + "/")
            let isTopLevel = url.deletingLastPathComponent().path == home.path
                && protectedNames.contains(url.lastPathComponent)
            // Never remove an excluded path, or a folder that holds one,
            // even if the scan results are older than the exclusion.
            let path = url.path
            let touchesExclusion = excludedPaths.contains {
                path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/")
            }
            guard isInsideHome, !isTopLevel, !touchesExclusion else {
                report.failed.append(job.url)
                continue
            }

            do {
                if job.permanent {
                    try fm.removeItem(at: url)
                } else {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                }
                report.removed.insert(job.url)
                report.freed += job.size
            } catch {
                report.failed.append(job.url)
            }
        }
        return report
    }
}
