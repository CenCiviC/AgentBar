import Foundation
import Combine
import SwiftUI
import AppKit

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

struct PortInfo: Identifiable {
    var id: String { "\(pid):\(port)" }
    let port: Int
    let address: String
    let pid: Int32
    let processName: String
    let agentKind: AgentKind?
}

struct AgentProcess: Identifiable, Hashable {
    let id: Int32
    let kind: AgentKind
    let ownerKind: AgentKind?
    let ownerPid: Int32?
    let name: String
    let tty: String?
    let terminalLocation: String?
    let command: String
    let cpu: Double
    let memMB: Double
    let isZombie: Bool
}

private struct ProcessSnapshot {
    let pid: Int32
    let ppid: Int32
    let tty: String?
    let cpu: Double
    let rss: Double
    let stat: String
    let command: String
    let executableName: String
}

private struct TmuxPane {
    let tty: String
    let sessionName: String
    let windowIndex: String
    let paneIndex: String
    let paneID: String

    var displayName: String {
        "\(sessionName):\(windowIndex).\(paneIndex)"
    }

    var windowTarget: String {
        "\(sessionName):\(windowIndex)"
    }
}

private struct TmuxClient {
    let sessionName: String
    let pid: Int32
}

private struct TmuxState {
    var panesByTTY: [String: TmuxPane] = [:]
    var clientsBySession: [String: [TmuxClient]] = [:]
}

private struct TmuxFlashState {
    let token: UUID
    let originalStyle: String?
}

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var processes: [AgentProcess] = []
    @Published var ports: [PortInfo] = []
    @Published var lastRefresh: Date = .now

    private var timer: Timer?
    private let detectableKinds: [AgentKind] = [.claude, .codex, .gemini, .mcp]
    private var latestSnapshotsByPid: [Int32: ProcessSnapshot] = [:]
    private var latestTmuxState = TmuxState()
    private var tmuxFlashStates: [String: TmuxFlashState] = [:]

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
        task.arguments = ["-axww", "-o", "pid=,ppid=,tty=,pcpu=,rss=,stat=,command="]

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
        let snapshots = output.split(separator: "\n").compactMap { parseSnapshot(String($0)) }
        let snapshotsByPid = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) })
        let tmuxState = loadTmuxState()
        latestSnapshotsByPid = snapshotsByPid
        latestTmuxState = tmuxState

        for snapshot in snapshots {
            if snapshot.pid == myPid { continue }

            let executableBasename = snapshot.executableName.lowercased()
            guard let kind = matchKind(argv0Basename: executableBasename, command: snapshot.command.lowercased()) else { continue }

            let displayName = friendlyName(kind: kind, snapshot: snapshot, snapshotsByPid: snapshotsByPid)
            let owner = kind == .mcp ? agentOwner(for: snapshot, snapshotsByPid: snapshotsByPid) : nil
            found.append(AgentProcess(
                id: snapshot.pid,
                kind: kind,
                ownerKind: owner?.kind,
                ownerPid: owner?.pid,
                name: displayName,
                tty: snapshot.tty,
                terminalLocation: terminalLocation(for: snapshot, tmuxState: tmuxState),
                command: snapshot.command,
                cpu: snapshot.cpu,
                memMB: snapshot.rss / 1024.0,
                isZombie: snapshot.stat.contains("Z")
            ))
        }

        self.processes = found
        self.lastRefresh = .now
        let agentByPid = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0.kind) })
        refreshPorts(agentByPid: agentByPid)
    }

    private func refreshPorts(agentByPid: [Int32: AgentKind]) {
        let result = runTask(launchPath: "/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-F", "pcn"])
        guard result.status == 0 else { return }

        var seen = Set<String>()
        var found: [PortInfo] = []
        var currentPid: Int32?
        var currentCommand: String?

        for line in result.output.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("p"), let pid = Int32(s.dropFirst()) {
                currentPid = pid
                currentCommand = nil
            } else if s.hasPrefix("c") {
                currentCommand = String(s.dropFirst())
            } else if s.hasPrefix("n"), let pid = currentPid {
                let name = String(s.dropFirst())
                guard let colonIdx = name.lastIndex(of: ":"),
                      let port = Int(name[name.index(after: colonIdx)...]),
                      port > 0 else { continue }
                let address = String(name[..<colonIdx])
                let key = "\(pid):\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let displayName: String
                if let snapshot = latestSnapshotsByPid[pid] {
                    displayName = friendlyName(executableName: snapshot.executableName, command: snapshot.command)
                } else {
                    displayName = currentCommand ?? "unknown"
                }
                found.append(PortInfo(
                    port: port,
                    address: address,
                    pid: pid,
                    processName: displayName,
                    agentKind: agentByPid[pid]
                ))
            }
        }

        let containerNames = containerPortNames(for: found)
        self.ports = found.map { port in
            guard let name = containerNames[port.port] else { return port }
            return PortInfo(port: port.port, address: port.address, pid: port.pid,
                            processName: name, agentKind: port.agentKind)
        }.sorted { $0.port < $1.port }
    }

    private func containerPortNames(for ports: [PortInfo]) -> [Int: String] {
        let portNumbers = Set(ports.map { $0.port })
        var map: [Int: String] = [:]
        for runtime in ["docker", "podman", "nerdctl"] {
            containerPortMap(runtime: runtime).forEach { port, name in
                if portNumbers.contains(port) {
                    map[port] = "\(name) (\(runtime))"
                }
            }
        }
        return map
    }

    private func containerPortMap(runtime: String) -> [Int: String] {
        guard let path = executablePath(named: runtime) else { return [:] }
        let result = runTask(launchPath: path, arguments: ["ps", "--format", "{{.Names}}\t{{.Ports}}"])
        guard result.status == 0 else { return [:] }

        var map: [Int: String] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let containerName = String(parts[0])
            for mapping in parts[1].split(separator: ",") {
                let s = mapping.trimmingCharacters(in: .whitespaces)
                guard let arrowIdx = s.range(of: "->") else { continue }
                let hostPart = String(s[..<arrowIdx.lowerBound])
                let portStr = hostPart.split(separator: ":").last.map(String.init) ?? hostPart
                if let hostPort = Int(portStr) { map[hostPort] = containerName }
            }
        }
        return map
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

    private func parseSnapshot(_ line: String) -> ProcessSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 7,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1]),
              let cpu = Double(parts[3]),
              let rss = Double(parts[4]) else { return nil }

        let command = parts[6...].joined(separator: " ")
        let executableName = executableName(from: command, fallbackToken: parts[6])
        return ProcessSnapshot(
            pid: pid,
            ppid: ppid,
            tty: normalizedTTY(parts[2]),
            cpu: cpu,
            rss: rss,
            stat: parts[5],
            command: command,
            executableName: executableName
        )
    }

    private func executableName(from command: String, fallbackToken: String) -> String {
        let executable = appExecutablePath(from: command) ?? fallbackToken
        return URL(fileURLWithPath: executable).lastPathComponent
    }

    /// `ps` prints argv as a plain string, so paths containing spaces are not
    /// recoverable in the general case. App bundles have a stable marker we can
    /// use to keep names like "Google Chrome Helper" intact.
    private func appExecutablePath(from command: String) -> String? {
        let marker = ".app/Contents/MacOS/"
        guard let markerRange = command.range(of: marker, options: .backwards) else { return nil }

        let afterMarker = command[markerRange.upperBound...]
        let argumentBoundary = afterMarker.range(of: " -")
        let executableEnd = argumentBoundary?.lowerBound ?? command.endIndex
        return String(command[..<executableEnd])
    }

    private func terminalLocation(for snapshot: ProcessSnapshot, tmuxState: TmuxState) -> String? {
        guard let tty = snapshot.tty else { return nil }
        if let pane = tmuxState.panesByTTY[tty] {
            return "tmux \(pane.displayName)"
        }
        return tty
    }

    private func normalizedTTY(_ rawTTY: String) -> String? {
        let trimmed = rawTTY.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??", trimmed != "-" else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private func friendlyName(kind: AgentKind, snapshot: ProcessSnapshot, snapshotsByPid: [Int32: ProcessSnapshot]) -> String {
        if kind == .mcp,
           let mcpName = mcpFriendlyName(for: snapshot, snapshotsByPid: snapshotsByPid) {
            return mcpName
        }

        return friendlyName(executableName: snapshot.executableName, command: snapshot.command)
    }

    /// Bare basenames like "node" or "npm" don't tell you which agent is running.
    /// For generic runtimes, append the identifying argument (package or script)
    /// so the row title reads e.g. "npm exec @executeautomation/playwright-mcp-server"
    /// instead of just "npm".
    private func friendlyName(executableName basename: String, command: String) -> String {
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

    private func mcpFriendlyName(for snapshot: ProcessSnapshot, snapshotsByPid: [Int32: ProcessSnapshot]) -> String? {
        let genericName = friendlyName(executableName: snapshot.executableName, command: snapshot.command)
        let lowerCommand = snapshot.command.lowercased()

        if let identifier = mcpIdentifier(in: snapshot.command) {
            return genericName == snapshot.executableName ? identifier : genericName
        }

        if let browser = playwrightMCPBrowserName(in: snapshot.command) {
            let owner = mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid) ?? "Playwright MCP"
            return "\(humanizedMCPIdentifier(owner)) · \(playwrightChildName(executableName: snapshot.executableName, browser: browser))"
        }

        if lowerCommand.contains("ms-playwright") {
            let owner = mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid) ?? "Playwright MCP"
            return "\(humanizedMCPIdentifier(owner)) · \(genericName)"
        }

        if let ancestor = mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid) {
            return "\(humanizedMCPIdentifier(ancestor)) · \(genericName)"
        }

        return nil
    }

    private func mcpAncestorIdentifier(for snapshot: ProcessSnapshot, snapshotsByPid: [Int32: ProcessSnapshot]) -> String? {
        var nextPid = snapshot.ppid
        var seen: Set<Int32> = [snapshot.pid]

        for _ in 0..<8 {
            guard nextPid > 0,
                  !seen.contains(nextPid),
                  let parent = snapshotsByPid[nextPid] else { return nil }

            if let identifier = mcpIdentifier(in: parent.command) {
                return identifier
            }

            if playwrightMCPBrowserName(in: parent.command) != nil || parent.command.lowercased().contains("ms-playwright") {
                return "Playwright MCP"
            }

            seen.insert(nextPid)
            nextPid = parent.ppid
        }

        return nil
    }

    private func agentOwner(for snapshot: ProcessSnapshot, snapshotsByPid: [Int32: ProcessSnapshot]) -> (kind: AgentKind, pid: Int32)? {
        var nextPid = snapshot.ppid
        var seen: Set<Int32> = [snapshot.pid]
        let agentKinds: [AgentKind] = [.claude, .codex, .gemini]

        for _ in 0..<12 {
            guard nextPid > 0,
                  !seen.contains(nextPid),
                  let parent = snapshotsByPid[nextPid] else { return nil }

            let basename = parent.executableName.lowercased()
            let command = parent.command.lowercased()
            for kind in agentKinds {
                let rules = kind.rules
                if rules.basenames.contains(basename) { return (kind, parent.pid) }
                if rules.commandSubstrings.contains(where: { command.contains($0) }) { return (kind, parent.pid) }
            }

            seen.insert(nextPid)
            nextPid = parent.ppid
        }

        return nil
    }

    private func mcpIdentifier(in command: String) -> String? {
        let tokens = mcpSearchTokens(from: command)

        for token in tokens {
            let lower = token.lowercased()
            if lower.contains("@modelcontextprotocol/") ||
                lower.contains("@playwright/mcp") ||
                lower.contains("playwright-mcp-server") {
                return prettifyMCPIdentifier(token)
            }
        }

        for token in tokens {
            let lower = token.lowercased()
            guard !isPlaywrightBrowserProfileToken(lower) else { continue }

            if lower.hasPrefix("mcp-server") ||
                lower.hasSuffix("-mcp-server") ||
                lower.hasPrefix("mcp-") {
                return prettifyMCPIdentifier(token)
            }
        }

        return nil
    }

    private func playwrightMCPBrowserName(in command: String) -> String? {
        for token in mcpSearchTokens(from: command) {
            let lower = token.lowercased()
            guard isPlaywrightBrowserProfileToken(lower) else { continue }

            let suffix = lower.dropFirst("mcp-".count)
            guard let browser = suffix.split(separator: "-").first else { continue }
            switch browser {
            case "chrome", "chromium":
                return "Chrome"
            case "msedge", "edge":
                return "Edge"
            case "firefox":
                return "Firefox"
            case "webkit":
                return "WebKit"
            default:
                continue
            }
        }

        return nil
    }

    private func isPlaywrightBrowserProfileToken(_ token: String) -> Bool {
        token.hasPrefix("mcp-chrome-") ||
            token.hasPrefix("mcp-chromium-") ||
            token.hasPrefix("mcp-msedge-") ||
            token.hasPrefix("mcp-edge-") ||
            token.hasPrefix("mcp-firefox-") ||
            token.hasPrefix("mcp-webkit-")
    }

    private func playwrightChildName(executableName: String, browser: String) -> String {
        let name = executableName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "Google" {
            return "\(browser) Browser"
        }
        return name
    }

    private func mcpSearchTokens(from command: String) -> [String] {
        var tokens: [String] = []
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)

        for word in words {
            let cleaned = cleanCommandToken(word)
            appendSearchToken(cleaned, to: &tokens)

            if let equalsIndex = cleaned.firstIndex(of: "=") {
                appendSearchToken(String(cleaned[cleaned.index(after: equalsIndex)...]), to: &tokens)
            }

            for component in cleaned.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
                appendSearchToken(String(component), to: &tokens)
            }
        }

        return tokens
    }

    private func appendSearchToken(_ token: String, to tokens: inout [String]) {
        let cleaned = cleanCommandToken(token)
        guard !cleaned.isEmpty else { return }
        tokens.append(cleaned)
    }

    private func cleanCommandToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`<>[]{}(),;"))
    }

    private func prettifyMCPIdentifier(_ token: String) -> String {
        let strippedVersion = stripNPMVersion(from: cleanCommandToken(token))
        return prettifyArg(strippedVersion)
    }

    private func stripNPMVersion(from token: String) -> String {
        if token.hasPrefix("@"),
           let slashIndex = token.firstIndex(of: "/") {
            let packageNameStart = token.index(after: slashIndex)
            if let versionIndex = token[packageNameStart...].firstIndex(of: "@") {
                return String(token[..<versionIndex])
            }
            return token
        }

        if let versionIndex = token.firstIndex(of: "@") {
            return String(token[..<versionIndex])
        }

        return token
    }

    private func humanizedMCPIdentifier(_ identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower == "@playwright/mcp" ||
            lower.contains("playwright-mcp-server") ||
            lower == "playwright mcp" {
            return "Playwright MCP"
        }

        return identifier
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

    func killGracefully(_ pid: Int32, processName: String) {
        kill(pid, force: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
                guard self.processes.contains(where: { $0.id == pid }) else { return }
                let alert = NSAlert()
                alert.messageText = "Process didn't exit"
                alert.informativeText = "\(processName) is still running after the quit signal. Force kill it now?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Force Kill")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.kill(pid, force: true)
                }
            }
        }
    }

    func killAll(force: Bool = false) {
        for p in processes { kill(p.id, force: force) }
    }

    func killAll(of kind: AgentKind, force: Bool = false) {
        for p in processes where p.kind == kind { kill(p.id, force: force) }
    }

    func focus(_ process: AgentProcess) {
        if let tty = process.tty,
           let pane = latestTmuxState.panesByTTY[tty] ?? loadTmuxState().panesByTTY[tty] {
            _ = runTmux(arguments: ["select-window", "-t", pane.windowTarget])
            _ = runTmux(arguments: ["select-pane", "-t", pane.paneID])
            _ = activateTmuxClient(for: pane) ?? activateAncestorApp(for: process.id) ?? activateLikelyTerminalApp()
            flashTmuxPaneSurface(for: pane)
            return
        }

        _ = activateAncestorApp(for: process.id) ?? activateLikelyTerminalApp()
    }

    private func loadTmuxState() -> TmuxState {
        guard let tmux = executablePath(named: "tmux") else { return TmuxState() }

        let separator = "\u{1F}"
        let panesFormat = [
            "#{pane_tty}",
            "#{session_name}",
            "#{window_index}",
            "#{pane_index}",
            "#{pane_id}",
        ].joined(separator: separator)

        var state = TmuxState()
        let panesResult = runTask(launchPath: tmux, arguments: ["list-panes", "-a", "-F", panesFormat])
        if panesResult.status == 0 {
            for line in panesResult.output.split(separator: "\n").map(String.init) {
                let fields = line.components(separatedBy: separator)
                guard fields.count >= 5,
                      let tty = normalizedTTY(fields[0]) else { continue }

                state.panesByTTY[tty] = TmuxPane(
                    tty: tty,
                    sessionName: fields[1],
                    windowIndex: fields[2],
                    paneIndex: fields[3],
                    paneID: fields[4]
                )
            }
        }

        let clientsFormat = [
            "#{session_name}",
            "#{client_pid}",
        ].joined(separator: separator)

        let clientsResult = runTask(launchPath: tmux, arguments: ["list-clients", "-F", clientsFormat])
        if clientsResult.status == 0 {
            for line in clientsResult.output.split(separator: "\n").map(String.init) {
                let fields = line.components(separatedBy: separator)
                guard fields.count >= 2,
                      let pid = Int32(fields[1]) else { continue }

                let client = TmuxClient(sessionName: fields[0], pid: pid)
                state.clientsBySession[client.sessionName, default: []].append(client)
            }
        }

        return state
    }

    @discardableResult
    private func runTmux(arguments: [String]) -> Bool {
        guard let tmux = executablePath(named: "tmux") else { return false }
        return runTask(launchPath: tmux, arguments: arguments).status == 0
    }

    private func flashTmuxPaneSurface(for pane: TmuxPane) {
        let target = pane.paneID

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.applyTmuxPaneFlash(target: target)
        }
    }

    private func applyTmuxPaneFlash(target: String) {
        let originalStyle: String?
        if let existingState = tmuxFlashStates[target] {
            originalStyle = existingState.originalStyle
        } else {
            let result = runTmuxOutput(arguments: [
                "show-option",
                "-pqv",
                "-t",
                target,
                "window-active-style",
            ])
            let style = result.status == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            originalStyle = style.isEmpty ? nil : style
        }

        let token = UUID()
        tmuxFlashStates[target] = TmuxFlashState(token: token, originalStyle: originalStyle)

        let flashStyle = computeFlashStyle(originalStyle: originalStyle, target: target)
        _ = runTmux(arguments: [
            "set-option",
            "-p",
            "-t",
            target,
            "window-active-style",
            flashStyle,
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self,
                  self.tmuxFlashStates[target]?.token == token else { return }

            let originalStyle = self.tmuxFlashStates[target]?.originalStyle
            self.tmuxFlashStates[target] = nil

            if let originalStyle {
                _ = self.runTmux(arguments: [
                    "set-option",
                    "-p",
                    "-t",
                    target,
                    "window-active-style",
                    originalStyle,
                ])
            } else {
                _ = self.runTmux(arguments: [
                    "set-option",
                    "-pu",
                    "-t",
                    target,
                    "window-active-style",
                ])
            }
        }
    }

    private func computeFlashStyle(originalStyle: String?, target: String) -> String {
        if let style = originalStyle, let lightened = lightenedTmuxStyle(style) {
            return lightened
        }
        // Pane has no explicit style — try the global window-style fallback
        let globalResult = runTmuxOutput(arguments: ["show-option", "-gqv", "window-style"])
        let globalStyle = globalResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !globalStyle.isEmpty, let lightened = lightenedTmuxStyle(globalStyle) {
            return lightened
        }
        return "bg=colour240"
    }

    private func lightenedTmuxStyle(_ style: String) -> String? {
        guard let bgValue = extractBgValue(from: style),
              let lightened = lightenColor(bgValue) else { return nil }
        return style.replacingOccurrences(of: "bg=\(bgValue)", with: "bg=\(lightened)")
    }

    private func extractBgValue(from style: String) -> String? {
        for part in style.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("bg=") { return String(trimmed.dropFirst(3)) }
        }
        return nil
    }

    private func lightenColor(_ color: String) -> String? {
        let lower = color.lowercased()
        if lower.hasPrefix("#") && lower.count == 7 {
            return blendHexWithWhite(lower, factor: 0.25)
        }
        if lower.hasPrefix("colour"), let index = Int(lower.dropFirst(6)) {
            return "colour\(lightenColourIndex(index))"
        }
        return nil
    }

    private func blendHexWithWhite(_ hex: String, factor: Double) -> String {
        let r = Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 0
        let g = Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 0
        let b = Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 0
        let nr = min(255, r + Int(Double(255 - r) * factor))
        let ng = min(255, g + Int(Double(255 - g) * factor))
        let nb = min(255, b + Int(Double(255 - b) * factor))
        return String(format: "#%02x%02x%02x", nr, ng, nb)
    }

    private func lightenColourIndex(_ index: Int) -> Int {
        switch index {
        case 0..<8:   return index + 8          // standard → bright variant
        case 8..<16:  return index               // already bright
        case 16..<232:                           // 6×6×6 color cube
            let i = index - 16
            let b = i % 6, g = (i / 6) % 6, r = i / 36
            return 16 + 36 * min(5, r + 1) + 6 * min(5, g + 1) + min(5, b + 1)
        default:      return min(255, index + 4) // grayscale ramp 232-255
        }
    }

    private func runTmuxOutput(arguments: [String]) -> (status: Int32, output: String) {
        guard let tmux = executablePath(named: "tmux") else { return (-1, "") }
        return runTask(launchPath: tmux, arguments: arguments)
    }

    private func executablePath(named name: String) -> String? {
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let path = ProcessInfo.processInfo.environment["PATH"] ?? fallbackPath
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        for directory in fallbackPath.split(separator: ":").map(String.init) {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func runTask(launchPath: String, arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return (-1, "")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func activateTmuxClient(for pane: TmuxPane) -> Int32? {
        let clients = latestTmuxState.clientsBySession[pane.sessionName] ?? loadTmuxState().clientsBySession[pane.sessionName] ?? []
        for client in clients {
            if let ownerPID = activateAncestorApp(for: client.pid) {
                return ownerPID
            }
        }

        return activateLikelyTerminalApp()
    }

    private func activateAncestorApp(for pid: Int32) -> Int32? {
        var nextPid = pid
        var seen: Set<Int32> = []

        for _ in 0..<16 {
            guard !seen.contains(nextPid),
                  let snapshot = latestSnapshotsByPid[nextPid] else { return nil }

            if isTerminalAppProcess(snapshot),
               let app = NSRunningApplication(processIdentifier: snapshot.pid) {
                return app.activate(options: [.activateAllWindows]) ? snapshot.pid : nil
            }

            seen.insert(nextPid)
            nextPid = snapshot.ppid
        }

        return nil
    }

    private func isTerminalAppProcess(_ snapshot: ProcessSnapshot) -> Bool {
        if snapshot.command.contains(".app/Contents/MacOS/") {
            return knownTerminalExecutableNames.contains(snapshot.executableName.lowercased())
        }

        return false
    }

    private var knownTerminalExecutableNames: Set<String> {
        [
            "terminal",
            "iterm2",
            "ghostty",
            "wezterm-gui",
            "kitty",
            "alacritty",
            "warp",
        ]
    }

    @discardableResult
    private func activateLikelyTerminalApp() -> Int32? {
        let bundleIdentifiers = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "dev.warp.Warp-Stable",
        ]

        for identifier in bundleIdentifiers {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
                if app.activate(options: [.activateAllWindows]) {
                    return app.processIdentifier
                }
            }
        }

        return nil
    }

    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemMB: Double { processes.reduce(0) { $0 + $1.memMB } }

    func count(of kind: AgentKind) -> Int {
        processes.filter { $0.kind == kind }.count
    }
}
