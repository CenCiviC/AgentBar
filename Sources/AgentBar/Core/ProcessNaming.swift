import Foundation

enum ProcessNaming {
    static func friendlyName(
        kind: AgentKind,
        snapshot: ProcessSnapshot,
        snapshotsByPid: [Int32: ProcessSnapshot]) -> String
    {
        if kind == .mcp,
           let mcpName = mcpFriendlyName(for: snapshot, snapshotsByPid: snapshotsByPid)
        {
            return mcpName
        }
        return self.friendlyName(executableName: snapshot.executableName, command: snapshot.command)
    }

    /// Bare basenames like "node" or "npm" don't tell you which agent is running.
    /// For generic runtimes, append the identifying argument (package or script).
    static func friendlyName(executableName basename: String, command: String) -> String {
        let runtimes: Set = [
            "node", "npm", "npx", "yarn", "pnpm", "bun", "bunx", "deno",
            "python", "python3", "ruby", "uv", "uvx",
            "sh", "bash", "zsh",
        ]
        guard runtimes.contains(basename.lowercased()) else { return basename }

        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count > 1 else { return basename }

        let args = Array(tokens.dropFirst()).filter { !$0.hasPrefix("-") }
        guard !args.isEmpty else { return basename }

        let lowerBase = basename.lowercased()
        if ["npm", "yarn", "pnpm"].contains(lowerBase) {
            let sub = args[0]
            if args.count >= 2 { return "\(basename) \(sub) \(self.prettifyArg(args[1]))" }
            return "\(basename) \(sub)"
        }

        return "\(basename) \(self.prettifyArg(args[0]))"
    }

    static func terminalLocation(for snapshot: ProcessSnapshot, panesByTTY: [String: TmuxPane]) -> String? {
        guard let tty = snapshot.tty else { return nil }
        if let pane = panesByTTY[tty] { return "tmux \(pane.displayName)" }
        return tty
    }

    static func mcpIdentifier(in command: String) -> String? {
        let tokens = self.searchTokens(from: command)

        for token in tokens {
            let lower = token.lowercased()
            if lower.contains("@modelcontextprotocol/") ||
                lower.contains("@playwright/mcp") ||
                lower.contains("playwright-mcp-server")
            {
                return self.prettifyMCPIdentifier(token)
            }
        }

        for token in tokens {
            let lower = token.lowercased()
            guard !self.isPlaywrightBrowserProfileToken(lower) else { continue }
            if lower.hasPrefix("mcp-server") ||
                lower.hasSuffix("-mcp-server") ||
                lower.hasPrefix("mcp-")
            {
                return self.prettifyMCPIdentifier(token)
            }
        }

        return nil
    }

    static func playwrightMCPBrowserName(in command: String) -> String? {
        for token in self.searchTokens(from: command) {
            let lower = token.lowercased()
            guard self.isPlaywrightBrowserProfileToken(lower) else { continue }
            let suffix = lower.dropFirst("mcp-".count)
            guard let browser = suffix.split(separator: "-").first else { continue }
            switch browser {
            case "chrome", "chromium": return "Chrome"
            case "msedge", "edge": return "Edge"
            case "firefox": return "Firefox"
            case "webkit": return "WebKit"
            default: continue
            }
        }
        return nil
    }

    static func humanizedMCPIdentifier(_ identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower == "@playwright/mcp" ||
            lower.contains("playwright-mcp-server") ||
            lower == "playwright mcp"
        {
            return "Playwright MCP"
        }
        return identifier
    }

    /// Keep scoped npm packages and short tokens intact; collapse absolute paths to basename.
    static func prettifyArg(_ token: String) -> String {
        if token.hasPrefix("@") { return token }
        if !token.contains("/") { return token }
        return URL(fileURLWithPath: token).lastPathComponent
    }

    // MARK: - Private

    private static func mcpFriendlyName(
        for snapshot: ProcessSnapshot,
        snapshotsByPid: [Int32: ProcessSnapshot]) -> String?
    {
        let genericName = self.friendlyName(executableName: snapshot.executableName, command: snapshot.command)
        let lowerCommand = snapshot.command.lowercased()

        if let identifier = mcpIdentifier(in: snapshot.command) {
            return genericName == snapshot.executableName ? identifier : genericName
        }

        if let browser = playwrightMCPBrowserName(in: snapshot.command) {
            let owner = ProcessHierarchy.mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid)
                ?? "Playwright MCP"
            return "\(self.humanizedMCPIdentifier(owner)) · \(self.playwrightChildName(executableName: snapshot.executableName, browser: browser))"
        }

        if lowerCommand.contains("ms-playwright") {
            let owner = ProcessHierarchy.mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid)
                ?? "Playwright MCP"
            return "\(self.humanizedMCPIdentifier(owner)) · \(genericName)"
        }

        if let ancestor = ProcessHierarchy.mcpAncestorIdentifier(for: snapshot, snapshotsByPid: snapshotsByPid) {
            return "\(self.humanizedMCPIdentifier(ancestor)) · \(genericName)"
        }

        return nil
    }

    private static func playwrightChildName(executableName: String, browser: String) -> String {
        let name = executableName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "Google" { return "\(browser) Browser" }
        return name
    }

    private static func isPlaywrightBrowserProfileToken(_ token: String) -> Bool {
        token.hasPrefix("mcp-chrome-") ||
            token.hasPrefix("mcp-chromium-") ||
            token.hasPrefix("mcp-msedge-") ||
            token.hasPrefix("mcp-edge-") ||
            token.hasPrefix("mcp-firefox-") ||
            token.hasPrefix("mcp-webkit-")
    }

    private static func prettifyMCPIdentifier(_ token: String) -> String {
        self.prettifyArg(self.stripNPMVersion(from: self.cleanToken(token)))
    }

    private static func stripNPMVersion(from token: String) -> String {
        if token.hasPrefix("@"), let slashIndex = token.firstIndex(of: "/") {
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

    private static func searchTokens(from command: String) -> [String] {
        var tokens: [String] = []
        for word in command.split(whereSeparator: \.isWhitespace).map(String.init) {
            let cleaned = self.cleanToken(word)
            self.appendToken(cleaned, to: &tokens)
            if let equalsIndex = cleaned.firstIndex(of: "=") {
                self.appendToken(String(cleaned[cleaned.index(after: equalsIndex)...]), to: &tokens)
            }
            for component in cleaned.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
                self.appendToken(String(component), to: &tokens)
            }
        }
        return tokens
    }

    private static func appendToken(_ token: String, to tokens: inout [String]) {
        let cleaned = self.cleanToken(token)
        guard !cleaned.isEmpty else { return }
        tokens.append(cleaned)
    }

    private static func cleanToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`<>[]{}(),;"))
    }
}
