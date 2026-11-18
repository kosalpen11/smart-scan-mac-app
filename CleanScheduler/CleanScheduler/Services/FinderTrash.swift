import AppKit

// MARK: - Finder fallback

enum FinderTrash {
    /// Empties the whole Trash through Finder. Used only when ~/.Trash can't be listed.
    /// NSAppleScript isn't thread-safe, so this stays on the main actor.
    @MainActor
    static func emptyAll() throws {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw CleanError.finderFailed(message)
        }
    }
}
