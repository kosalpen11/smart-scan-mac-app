import Foundation

// MARK: - Errors

enum CleanError: LocalizedError, Sendable {
    case toolMissing(CommandTool)
    case dockerNotRunning
    case commandFailed(String)
    case invalidFolder(String)
    case authFailed(String)
    case finderFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool): tool.missingMessage
        case .dockerNotRunning: "Docker isn't running. Open Docker Desktop, wait for it to start, then try again."
        case .commandFailed(let output): "The command failed: \(output)"
        case .invalidFolder(let message): message
        case .authFailed(let message): message
        case .finderFailed(let message):
            "Finder couldn't empty the Trash (\(message)). Allow Clean Scheduler to control Finder in System Settings › Privacy & Security › Automation, then try again."
        }
    }
}
