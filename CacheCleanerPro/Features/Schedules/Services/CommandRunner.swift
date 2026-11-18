import Foundation

/// Runs preset commands with Process (no shell).
enum CommandRunner {
    struct Output: Sendable {
        var status: Int32
        var text: String
    }

    nonisolated static func executable(for tool: CommandTool) -> URL? {
        tool.candidatePaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    nonisolated static func isInstalled(_ tool: CommandTool) -> Bool { executable(for: tool) != nil }

    /// Runs the tool and returns combined stdout and stderr.
    nonisolated static func run(_ tool: CommandTool, arguments: [String]) throws -> Output {
        guard let url = executable(for: tool) else { throw CleanError.toolMissing(tool) }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments

        // Apps opened from Finder get a minimal PATH; tools like docker and brew call helpers on it.
        var environment = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/Docker.app/Contents/Resources/bin",
                     "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = (extra + [environment["PATH"] ?? ""]).joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if tool == .docker, isDockerDaemonDown(text) { throw CleanError.dockerNotRunning }
        return Output(status: process.terminationStatus, text: text)
    }

    nonisolated static func isDockerDaemonDown(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("cannot connect to the docker daemon")
            || lower.contains("is the docker daemon running")
            || lower.contains("error during connect")
    }

    // MARK: Preview

    /// Runs the read-only preview command and decides whether there is anything to clean.
    nonisolated static func preview(_ preset: CommandPreset) throws -> CleanPreview {
        let output = try run(preset.tool, arguments: preset.previewArguments)
        guard output.status == 0 else {
            throw CleanError.commandFailed(output.text.isEmpty ? "exit code \(output.status)" : output.text)
        }
        let text = output.text
        let hasWork: Bool
        switch preset {
        case .homebrew:
            hasWork = !text.isEmpty
        case .simulators:
            hasWork = text.contains("(unavailable")
        case .dockerSystem:
            hasWork = dockerReclaimable(text, rows: ["Images", "Containers", "Build Cache"])
        case .dockerBuildCache:
            hasWork = dockerReclaimable(text, rows: ["Build Cache"])
        }
        let shown = text.isEmpty ? "Nothing to clean." : text
        return CleanPreview(content: .commandOutput(shown), hasWork: hasWork, permanent: true)
    }

    /// Reads the RECLAIMABLE column of `docker system df` for the given rows.
    nonisolated static func dockerReclaimable(_ text: String, rows: [String]) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        guard let header = lines.first(where: { $0.contains("RECLAIMABLE") }),
              let column = header.range(of: "RECLAIMABLE") else { return true }
        let offset = header.distance(from: header.startIndex, to: column.lowerBound)

        for line in lines where rows.contains(where: { line.hasPrefix($0) }) {
            guard line.count > offset else { continue }
            let value = line.dropFirst(offset).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty && !value.hasPrefix("0B") { return true }
        }
        return false
    }

    /// Best-effort bytes freed, from "Total reclaimed space: 1.2GB" (docker) or
    /// "freed approximately 1.2GB" (brew).
    nonisolated static func bytesFreed(in text: String) -> Int64 {
        let pattern = #"(?:reclaimed space:|freed approximately)\s*([0-9.]+)\s*([kKMGT]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numberRange]) else { return 0 }
        let multiplier: Double = switch text[unitRange].uppercased() {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(number * multiplier)
    }
}
