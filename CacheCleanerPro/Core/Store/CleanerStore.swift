import SwiftUI
import AppKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class CleanerStore {
    /// Shared so the scheduler, notifications and review window can reach it.
    static let shared = CleanerStore()

    enum Phase: Equatable { case idle, scanning, cleaning }

    // Scan state
    var phase: Phase = .idle
    var progress: Double = 0
    var progressLabel = ""
    var results: [CleanupCategory: CategoryResult] = [:]
    var selection: Set<URL> = []
    var lastScan: Date?
    var message: String?

    // Smart Clean
    var smartPicks: [SmartPick] = []
    var showSmartClean = false

    // System state
    var disk = DiskInfo.current()
    var hasFullDiskAccess = Permissions.hasFullDiskAccess
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    // Saved state
    var settings = AppSettings.load() {
        didSet { settings.save() }
    }
    var history: [CleanRecord] = CleanRecord.loadAll() {
        didSet { CleanRecord.saveAll(history) }
    }

    // MARK: Derived values

    var isBusy: Bool { phase != .idle }
    var hasScanned: Bool { lastScan != nil }
    var allItems: [CleanupItem] { results.values.flatMap(\.items) }
    var totalReclaimable: Int64 { results.values.reduce(0) { $0 + $1.totalSize } }
    var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var lifetimeFreed: Int64 { history.reduce(0) { $0 + $1.bytes } }

    func result(for category: CleanupCategory) -> CategoryResult? { results[category] }

    func selectedItems(in category: CleanupCategory) -> [CleanupItem] {
        (results[category]?.items ?? []).filter { selection.contains($0.url) }
    }

    func selectedSize(in category: CleanupCategory) -> Int64 {
        selectedItems(in: category).reduce(0) { $0 + $1.size }
    }

    var smartRecommendedSize: Int64 {
        smartPicks.filter(\.recommended).reduce(0) { $0 + $1.item.size }
    }

    // MARK: Selection

    func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { self.selection.contains(url) },
            set: { isOn in
                if isOn { self.selection.insert(url) } else { self.selection.remove(url) }
            }
        )
    }

    func setSelected(_ urls: some Sequence<URL>, _ isOn: Bool) {
        if isOn { selection.formUnion(urls) } else { selection.subtract(urls) }
    }

    func selectAll(in category: CleanupCategory, _ isOn: Bool) {
        setSelected((results[category]?.items ?? []).map(\.url), isOn)
    }

    // MARK: Scan

    func scan() async {
        guard !isBusy else { return }
        phase = .scanning
        progress = 0
        progressLabel = "Starting scan…"
        message = nil
        hasFullDiskAccess = Permissions.hasFullDiskAccess

        let options = ScanOptions(
            includeAppleCaches: settings.includeAppleCaches,
            largeFileThreshold: Int64(settings.largeFileThresholdMB) * 1_000_000,
            excludedPaths: settings.excludedPaths,
            ownBundleID: Bundle.main.bundleIdentifier ?? ""
        )
        let categories = CleanupCategory.allCases
        var newResults: [CleanupCategory: CategoryResult] = [:]
        var finished = 0

        await withTaskGroup(of: CategoryResult.self) { group in
            for category in categories {
                group.addTask { ScanEngine.scan(category, options: options) }
            }
            for await result in group {
                newResults[result.category] = result
                finished += 1
                progress = Double(finished) / Double(categories.count)
                progressLabel = "Checked \(result.category.title)"
            }
        }

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let scanned = newResults
        progressLabel = "Picking junk…"
        smartPicks = await Task.detached(priority: .userInitiated) {
            SmartRules.evaluate(scanned, runningBundleIDs: running)
        }.value

        results = newResults
        selection = Set(
            newResults.values
                .filter { $0.category.selectedByDefault }
                .flatMap { $0.items.map(\.url) }
        )
        lastScan = .now
        disk = DiskInfo.current()
        phase = .idle
    }

    // MARK: Clean

    func clean(_ urls: Set<URL>) async {
        guard !isBusy, !urls.isEmpty else { return }
        phase = .cleaning
        progressLabel = "Cleaning…"

        var jobs: [CleanJob] = []
        var touchedCategories: Set<CleanupCategory> = []
        for result in results.values {
            for item in result.items where urls.contains(item.url) {
                let permanent = settings.deletePermanently || result.category.alwaysPermanent
                jobs.append(CleanJob(url: item.url, size: item.size, permanent: permanent))
                touchedCategories.insert(result.category)
            }
        }

        let finalJobs = jobs
        let excludedPaths = settings.excludedPaths
        let report = await Task.detached(priority: .userInitiated) {
            Cleaner.run(finalJobs, excludedPaths: excludedPaths)
        }.value

        for category in Array(results.keys) {
            results[category]?.items.removeAll { report.removed.contains($0.url) }
        }
        selection.subtract(report.removed)
        smartPicks.removeAll { report.removed.contains($0.id) }
        disk = DiskInfo.current()

        if !report.removed.isEmpty {
            history.insert(CleanRecord(date: .now,
                                       bytes: report.freed,
                                       itemCount: report.removed.count,
                                       categories: Array(touchedCategories)), at: 0)
        }

        var text = "Cleaned \(report.freed.formattedBytes) from \(report.removed.count) items."
        let wentToTrash = jobs.contains { !$0.permanent && report.removed.contains($0.url) }
        if wentToTrash { text += " Empty the Trash to free the space." }
        if !report.failed.isEmpty {
            text += " \(report.failed.count) items were in use or protected and were skipped."
        }
        message = text
        phase = .idle
    }

    func cleanSelection() async { await clean(selection) }

    /// Opens the Smart Clean preview, scanning first if needed.
    func openSmartClean() async {
        if !hasScanned { await scan() }
        showSmartClean = true
    }

    // MARK: Exclusions

    func exclude(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !settings.excludedPaths.contains(path) else { return }
        settings.excludedPaths.append(path)
        // Rows inside the excluded path go away. Rows that contain it go too,
        // since cleaning them would remove it; the next scan lists what's around it.
        func overlaps(_ url: URL) -> Bool {
            url.path == path || url.path.hasPrefix(path + "/") || path.hasPrefix(url.path + "/")
        }
        var hidContainingFolder = false
        for category in Array(results.keys) {
            results[category]?.items.removeAll {
                if path.hasPrefix($0.url.path + "/") { hidContainingFolder = true }
                return overlaps($0.url)
            }
        }
        selection = selection.filter { !overlaps($0) }
        smartPicks.removeAll { overlaps($0.id) }
        if hidContainingFolder {
            message = "Scan again to see the rest of the folder that holds \(url.lastPathComponent)."
        }
    }

    func removeExclusion(_ path: String) {
        settings.excludedPaths.removeAll { $0 == path }
    }

    // MARK: System

    func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }
}
