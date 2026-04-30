import Foundation

struct ProcessSnapshot {
    let pid: Int32
    let ppid: Int32
    let tty: String?
    let cpu: Double
    let rss: Double
    let stat: String
    let command: String
    let executableName: String
}

enum ProcessParser {
    static let detectableKinds: [AgentKind] = [.claude, .codex, .gemini, .mcp]

    static func parse(psOutput: String) -> [ProcessSnapshot] {
        psOutput.split(separator: "\n").compactMap { self.parseSnapshot(String($0)) }
    }

    static func matchKind(argv0Basename: String, command: String) -> AgentKind? {
        for kind in self.detectableKinds {
            let rules = kind.rules
            if rules.basenames.contains(argv0Basename) { return kind }
            if rules.commandSubstrings.contains(where: { command.contains($0) }) { return kind }
        }
        return nil
    }

    static func normalizedTTY(_ rawTTY: String) -> String? {
        let trimmed = rawTTY.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??", trimmed != "-" else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    // MARK: - Private

    private static func parseSnapshot(_ line: String) -> ProcessSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 7,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1]),
              let cpu = Double(parts[3]),
              let rss = Double(parts[4]) else { return nil }

        let command = parts[6...].joined(separator: " ")
        return ProcessSnapshot(
            pid: pid,
            ppid: ppid,
            tty: self.normalizedTTY(parts[2]),
            cpu: cpu,
            rss: rss,
            stat: parts[5],
            command: command,
            executableName: self.resolveExecutableName(from: command, fallbackToken: parts[6]))
    }

    private static func resolveExecutableName(from command: String, fallbackToken: String) -> String {
        let executable = self.appExecutablePath(from: command) ?? fallbackToken
        return URL(fileURLWithPath: executable).lastPathComponent
    }

    /// App bundles have a stable ".app/Contents/MacOS/" marker we can use
    /// to keep names like "Google Chrome Helper" intact despite ps truncation.
    private static func appExecutablePath(from command: String) -> String? {
        let marker = ".app/Contents/MacOS/"
        guard let markerRange = command.range(of: marker, options: .backwards) else { return nil }
        let afterMarker = command[markerRange.upperBound...]
        let argumentBoundary = afterMarker.range(of: " -")
        let executableEnd = argumentBoundary?.lowerBound ?? command.endIndex
        return String(command[..<executableEnd])
    }
}
