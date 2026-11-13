import SwiftUI
import AppKit

// MARK: - Category groups

enum CategoryGroup: String, CaseIterable, Identifiable {
    case system = "System Junk"
    case developer = "Developer"
    case files = "Files & Backups"
    var id: String { rawValue }
}

enum SafetyLevel: Sendable {
    case safe, review

    var label: String { self == .safe ? "Safe to clean" : "Review first" }
    var color: Color { self == .safe ? .green : .orange }
}

enum ScanMode: Sendable {
    case children     // each item inside the folder is one row
    case wholeRoot    // the folder itself is one row
    case largeFiles   // search the folder for big files
}

// MARK: - Categories

enum CleanupCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case userCaches, logs, trash
    case derivedData, archives, deviceSupport, simulatorCaches, packageCaches, toolCaches
    case mailDownloads, iosBackups, installers, largeFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches:      return "App Caches"
        case .logs:            return "Logs"
        case .trash:           return "Trash"
        case .derivedData:     return "Xcode DerivedData"
        case .archives:        return "Xcode Archives"
        case .deviceSupport:   return "Device Support"
        case .simulatorCaches: return "Simulator Caches"
        case .packageCaches:   return "Package Caches"
        case .toolCaches:      return "Tool Caches (~/.cache)"
        case .mailDownloads:   return "Mail Attachments"
        case .iosBackups:      return "iPhone & iPad Backups"
        case .installers:      return "Installers"
        case .largeFiles:      return "Large Files"
        }
    }

    var subtitle: String {
        switch self {
        case .userCaches:      return "Temporary files apps rebuild on their own."
        case .logs:            return "Old diagnostic and crash logs."
        case .trash:           return "Files already in your Trash. Cleaning deletes them for good."
        case .derivedData:     return "Build files Xcode regenerates on the next build."
        case .archives:        return "Old app builds. Keep any you need for crash reports."
        case .deviceSupport:   return "Debug symbols for iOS and watchOS versions you used before."
        case .simulatorCaches: return "Caches the iOS Simulator rebuilds when needed."
        case .packageCaches:   return "npm and Gradle download caches."
        case .toolCaches:      return "Command-line tool caches. Some hold big downloads, like ML models, that are slow to get back."
        case .mailDownloads:   return "Copies of attachments you opened in Mail."
        case .iosBackups:      return "Device backups. Make sure you don't need them first."
        case .installers:      return ".dmg and .pkg files in Downloads you have likely installed."
        case .largeFiles:      return "Big files in Downloads, Desktop, Documents and Movies."
        }
    }

    var symbol: String {
        switch self {
        case .userCaches:      return "archivebox"
        case .logs:            return "doc.text"
        case .trash:           return "trash"
        case .derivedData:     return "hammer"
        case .archives:        return "shippingbox"
        case .deviceSupport:   return "cpu"
        case .simulatorCaches: return "ipad.and.iphone"
        case .packageCaches:   return "cube.box"
        case .toolCaches:      return "terminal"
        case .mailDownloads:   return "paperclip"
        case .iosBackups:      return "iphone"
        case .installers:      return "opticaldiscdrive"
        case .largeFiles:      return "externaldrive"
        }
    }

    var color: Color {
        switch self {
        case .userCaches:      return .blue
        case .logs:            return .gray
        case .trash:           return .red
        case .derivedData:     return .purple
        case .archives:        return .brown
        case .deviceSupport:   return .mint
        case .simulatorCaches: return .cyan
        case .packageCaches:   return .orange
        case .toolCaches:      return .green
        case .mailDownloads:   return .teal
        case .iosBackups:      return .indigo
        case .installers:      return .pink
        case .largeFiles:      return .yellow
        }
    }

    var group: CategoryGroup {
        switch self {
        case .userCaches, .logs, .trash: return .system
        case .derivedData, .archives, .deviceSupport, .simulatorCaches, .packageCaches, .toolCaches:
            return .developer
        case .mailDownloads, .iosBackups, .installers, .largeFiles: return .files
        }
    }

    var safety: SafetyLevel {
        switch self {
        case .userCaches, .logs, .derivedData, .deviceSupport, .simulatorCaches, .packageCaches:
            return .safe
        default:
            return .review
        }
    }

    /// Ticked automatically after a scan, and included in Smart Clean.
    var selectedByDefault: Bool { safety == .safe }

    /// Items here are removed for good, never moved to the Trash.
    var alwaysPermanent: Bool { self == .trash }

    /// Folders relative to the home folder.
    var roots: [String] {
        switch self {
        case .userCaches:      return ["Library/Caches"]
        case .logs:            return ["Library/Logs"]
        case .trash:           return [".Trash"]
        case .derivedData:     return ["Library/Developer/Xcode/DerivedData"]
        case .archives:        return ["Library/Developer/Xcode/Archives"]
        case .deviceSupport:   return ["Library/Developer/Xcode/iOS DeviceSupport",
                                       "Library/Developer/Xcode/watchOS DeviceSupport"]
        case .simulatorCaches: return ["Library/Developer/CoreSimulator/Caches"]
        case .packageCaches:   return [".npm/_cacache", ".gradle/caches"]
        case .toolCaches:      return [".cache"]
        case .mailDownloads:   return ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]
        case .iosBackups:      return ["Library/Application Support/MobileSync/Backup"]
        case .installers:      return ["Downloads"]
        case .largeFiles:      return ["Downloads", "Desktop", "Documents", "Movies"]
        }
    }

    var scanMode: ScanMode {
        switch self {
        case .packageCaches: return .wholeRoot
        case .largeFiles:    return .largeFiles
        default:             return .children
        }
    }

    var allowedExtensions: Set<String>? {
        self == .installers ? CleanupCategory.installerExtensions : nil
    }

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
}

// MARK: - Scan results

struct CleanupItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var modifiedSortKey: Date { modified ?? .distantPast }
}

struct CategoryResult: Sendable {
    let category: CleanupCategory
    var items: [CleanupItem]
    var accessDenied: Bool

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var deletePermanently = false
    var includeAppleCaches = false
    var scanOnLaunch = true
    var largeFileThresholdMB = 500
    var excludedPaths: [String] = []

    private static let key = "AppSettings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - History

struct CleanRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let bytes: Int64
    let itemCount: Int
    let categories: [CleanupCategory]

    private static let key = "CleanHistory.v1"

    static func loadAll() -> [CleanRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([CleanRecord].self, from: data) else {
            return []
        }
        return value
    }

    static func saveAll(_ records: [CleanRecord]) {
        if let data = try? JSONEncoder().encode(Array(records.prefix(200))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Disk

struct DiskInfo: Sendable {
    var total: Int64
    var available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return DiskInfo(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}

// MARK: - Permissions

enum Permissions {
    /// macOS doesn't offer an API to ask directly, so try reading a protected folder.
    static var hasFullDiskAccess: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Formatting

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
