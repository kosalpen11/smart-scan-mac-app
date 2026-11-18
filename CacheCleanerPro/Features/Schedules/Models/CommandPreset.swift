import Foundation

// MARK: - Command presets

/// A command-line tool a preset runs. Looked up in fixed locations, never via a shell.
enum CommandTool: String, Codable, Sendable {
    case docker, brew, xcrun

    var displayName: String {
        switch self {
        case .docker: "Docker"
        case .brew: "Homebrew"
        case .xcrun: "Xcode command line tools"
        }
    }

    var candidatePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .docker:
            return [
                "/opt/homebrew/bin/docker",
                "/usr/local/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker",
                home + "/Applications/Docker.app/Contents/Resources/bin/docker",
            ]
        case .brew:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .xcrun:
            return ["/usr/bin/xcrun", "/opt/homebrew/bin/xcrun", "/usr/local/bin/xcrun"]
        }
    }

    var missingMessage: String {
        switch self {
        case .docker: "Docker isn't installed. Install Docker Desktop, then try again."
        case .brew: "Homebrew isn't installed. Install it from brew.sh, then try again."
        case .xcrun: "Xcode isn't installed. Install Xcode from the App Store, then try again."
        }
    }
}

enum CommandPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case dockerSystem, dockerBuildCache, homebrew, simulators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dockerSystem: "Docker Cleanup"
        case .dockerBuildCache: "Docker Build Cache"
        case .homebrew: "Homebrew Cleanup"
        case .simulators: "Old Simulators"
        }
    }

    var symbol: String {
        switch self {
        case .dockerSystem: "shippingbox"
        case .dockerBuildCache: "hammer"
        case .homebrew: "mug"
        case .simulators: "iphone"
        }
    }

    var summary: String {
        switch self {
        case .dockerSystem: "Removes stopped containers, unused images, networks and build cache. Volumes are kept."
        case .dockerBuildCache: "Removes all Docker build cache."
        case .homebrew: "Removes old versions and downloads that Homebrew no longer needs."
        case .simulators: "Deletes simulators whose iOS version is no longer installed."
        }
    }

    var tool: CommandTool {
        switch self {
        case .dockerSystem, .dockerBuildCache: .docker
        case .homebrew: .brew
        case .simulators: .xcrun
        }
    }

    var cleanArguments: [String] {
        switch self {
        case .dockerSystem: ["system", "prune", "-af"]
        case .dockerBuildCache: ["builder", "prune", "-af"]
        case .homebrew: ["cleanup", "--prune=all"]
        case .simulators: ["simctl", "delete", "unavailable"]
        }
    }

    /// Read-only command whose output is shown before cleaning.
    var previewArguments: [String] {
        switch self {
        case .dockerSystem, .dockerBuildCache: ["system", "df"]
        case .homebrew: ["cleanup", "--prune=all", "-n"]
        case .simulators: ["simctl", "list", "devices", "unavailable"]
        }
    }

    var commandLine: String { ([tool.rawValue] + cleanArguments).joined(separator: " ") }
    var previewCommandLine: String { ([tool.rawValue] + previewArguments).joined(separator: " ") }
}
