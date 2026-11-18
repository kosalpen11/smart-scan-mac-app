import Foundation

/// Builds previews and performs the file and command part of a cleanup, off the main actor.
enum RuleEngine {
    nonisolated static func preview(_ rule: Rule) throws -> CleanPreview {
        switch rule.kind {
        case .folder:
            if let problem = FileCleaner.validateFolder(rule.folderPath) { throw CleanError.invalidFolder(problem) }
            let items = try FileCleaner.listFolder(rule.folderURL, olderThanDays: rule.olderThanDays)
            return CleanPreview(content: .items(items), hasWork: !items.isEmpty, permanent: rule.deletePermanently)

        case .trash:
            do {
                let items = try FileCleaner.listTrash(olderThanDays: rule.olderThanDays)
                return CleanPreview(content: .items(items), hasWork: !items.isEmpty, permanent: true)
            } catch {
                return CleanPreview(content: .trashUnreadable, hasWork: true, permanent: true)
            }

        case .command:
            return try CommandRunner.preview(rule.preset)
        }
    }

    /// Removes the previewed items (folder and readable-trash rules) or runs the command.
    /// The unreadable-trash case is handled by the caller on the main actor (Finder).
    nonisolated static func perform(_ rule: Rule, preview: CleanPreview) throws -> RuleResult {
        switch rule.kind {
        case .folder:
            // Re-check: the folder may have changed since the rule was saved.
            if let problem = FileCleaner.validateFolder(rule.folderPath) { throw CleanError.invalidFolder(problem) }
            let report = FileCleaner.remove(preview.items, from: rule.folderURL, permanently: rule.deletePermanently)
            return result(from: report, verb: rule.deletePermanently ? "Deleted" : "Moved to the Trash:")

        case .trash:
            let report = FileCleaner.remove(preview.items, from: FileCleaner.trashURL, permanently: true)
            return result(from: report, verb: "Deleted")

        case .command:
            let output = try CommandRunner.run(rule.preset.tool, arguments: rule.preset.cleanArguments)
            guard output.status == 0 else {
                throw CleanError.commandFailed(output.text.isEmpty ? "exit code \(output.status)" : output.text)
            }
            let freed = CommandRunner.bytesFreed(in: output.text)
            let lastLine = output.text.components(separatedBy: .newlines).last(where: { !$0.isEmpty }) ?? "Done."
            return RuleResult(date: Date(), succeeded: true, bytesFreed: freed, itemCount: 0, message: lastLine)
        }
    }

    nonisolated static func result(from report: FileCleaner.RemovalReport, verb: String) -> RuleResult {
        var message = "\(verb) \(Format.items(report.removedCount)), \(Format.bytes(report.bytesFreed))."
        if !report.failures.isEmpty {
            message += " \(report.failures.count) couldn't be removed: " + report.failures.prefix(3).joined(separator: " ")
        }
        return RuleResult(date: Date(), succeeded: report.failures.isEmpty, bytesFreed: report.bytesFreed,
                          itemCount: report.removedCount, message: message)
    }
}
