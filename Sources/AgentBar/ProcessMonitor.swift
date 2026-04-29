import Foundation
import Combine
import SwiftUI

enum AgentKind: String, CaseIterable, Hashable {
    case claude = "Claude"
    case codex = "Codex"
    case gemini = "Gemini"
    case mcp = "MCP"
    case other = "AI"

    var color: Color {
        switch self {
        case .claude: return .orange
        case .codex:  return .green
        case .gemini: return .blue
        case .mcp:    return .purple
        case .other:  return .gray
        }
    }

    /// Strict matching rules so we don't false-positive on apps like
    /// /Applications/CodexBar.app whose names merely *contain* "codex".
    /// A process matches if argv[0]'s basename equals one of `basenames`,
    /// or if the full command contains one of `commandSubstrings`.
    var rules: MatchRules {
        switch self {
        case .claude:
            return MatchRules(
                basenames: ["claude", "claude-code"],
                commandSubstrings: ["@anthropic-ai/claude-code", "anthropic-ai/claude"]
            )
        case .codex:
            return MatchRules(
                basenames: ["codex"],
                commandSubstrings: ["@openai/codex", "openai/codex"]
            )
        case .gemini:
            return MatchRules(
                basenames: ["gemini", "gemini-cli"],
                commandSubstrings: ["@google/gemini", "google/gemini-cli"]
            )
        case .mcp:
            return MatchRules(
                basenames: [],
                commandSubstrings: ["mcp-server", "@modelcontextprotocol", "mcp-"]
            )
        case .other:
            return MatchRules(basenames: [], commandSubstrings: [])
        }
    }
}

struct MatchRules {
    let basenames: [String]
    let commandSubstrings: [String]
}

struct AgentProcess: Identifiable, Hashable {
    let id: Int32
    let kind: AgentKind
    let name: String
    let command: String
    let cpu: Double
    let memMB: Double
    let isZombie: Bool
}

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var processes: [AgentProcess] = []
    @Published var lastRefresh: Date = .now

    private var timer: Timer?
    private let detectableKinds: [AgentKind] = [.claude, .codex, .gemini, .mcp]

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let task = Process()
        task.launchPath = "/bin/ps"
        // -ww disables column truncation so the command field is never clipped.
        // We deliberately omit `comm` because macOS truncates it to ~16 chars,
        // and when argv[0] contains spaces (e.g. "npm exec @foo/bar") the
        // truncated comm bleeds into our column splitting and corrupts parsing.
        task.arguments = ["-axww", "-o", "pid=,pcpu=,rss=,stat=,command="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return
        }

        // Drain the pipe BEFORE waiting; otherwise ps blocks once its
        // ~64KB stdout buffer fills, causing waitUntilExit to deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        let myPid = ProcessInfo.processInfo.processIdentifier
        var found: [AgentProcess] = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Double(parts[2]) else { continue }

            if pid == myPid { continue }

            let stat = parts[3]
            let command = parts[4...].joined(separator: " ")
            let argv0 = parts[4]
            let argv0Basename = URL(fileURLWithPath: argv0).lastPathComponent.lowercased()

            guard let kind = matchKind(argv0Basename: argv0Basename, command: command.lowercased()) else { continue }

            let displayName = friendlyName(executable: argv0, command: command)
            found.append(AgentProcess(
                id: pid,
                kind: kind,
                name: displayName,
                command: command,
                cpu: cpu,
                memMB: rss / 1024.0,
                isZombie: stat.contains("Z")
            ))
        }

        self.processes = found.sorted { $0.cpu > $1.cpu }
        self.lastRefresh = .now
    }

    private func matchKind(argv0Basename: String, command: String) -> AgentKind? {
        for kind in detectableKinds {
            let rules = kind.rules
            if rules.basenames.contains(argv0Basename) { return kind }
            if rules.commandSubstrings.contains(where: { command.contains($0) }) {
                return kind
            }
        }
        return nil
    }

    /// Bare basenames like "node" or "npm" don't tell you which agent is running.
    /// For generic runtimes, append the identifying argument (package or script)
    /// so the row title reads e.g. "npm exec @executeautomation/playwright-mcp-server"
    /// instead of just "npm".
    private func friendlyName(executable: String, command: String) -> String {
        let basename = URL(fileURLWithPath: executable).lastPathComponent
        let runtimes: Set<String> = [
            "node", "npm", "npx", "yarn", "pnpm", "bun", "bunx", "deno",
            "python", "python3", "ruby", "uv", "uvx",
            "sh", "bash", "zsh",
        ]
        guard runtimes.contains(basename.lowercased()) else { return basename }

        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count > 1 else { return basename }

        // Drop argv[0]; ignore flags so we can find the meaningful argument.
        let args = Array(tokens.dropFirst()).filter { !$0.hasPrefix("-") }
        guard !args.isEmpty else { return basename }

        // npm-family takes a subcommand (exec/run/start) + target.
        let lowerBase = basename.lowercased()
        if ["npm", "yarn", "pnpm"].contains(lowerBase) {
            let sub = args[0]
            if args.count >= 2 {
                return "\(basename) \(sub) \(prettifyArg(args[1]))"
            }
            return "\(basename) \(sub)"
        }

        return "\(basename) \(prettifyArg(args[0]))"
    }

    /// Keep scoped npm packages and short tokens intact; collapse absolute paths
    /// to their basename so titles don't get drowned in /Users/.../node_modules/...
    private func prettifyArg(_ token: String) -> String {
        if token.hasPrefix("@") { return token }
        if !token.contains("/") { return token }
        return URL(fileURLWithPath: token).lastPathComponent
    }

    func kill(_ pid: Int32, force: Bool = false) {
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = [force ? "-9" : "-15", String(pid)]
        try? task.run()
        task.waitUntilExit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func killAll(force: Bool = false) {
        for p in processes { kill(p.id, force: force) }
    }

    func killAll(of kind: AgentKind, force: Bool = false) {
        for p in processes where p.kind == kind { kill(p.id, force: force) }
    }

    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemMB: Double { processes.reduce(0) { $0 + $1.memMB } }

    func count(of kind: AgentKind) -> Int {
        processes.filter { $0.kind == kind }.count
    }
}
