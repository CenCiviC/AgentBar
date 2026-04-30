import Foundation

enum ProcessHierarchy {
    static func agentOwner(
        for snapshot: ProcessSnapshot,
        snapshotsByPid: [Int32: ProcessSnapshot]) -> (kind: AgentKind, pid: Int32)?
    {
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

    static func mcpAncestorIdentifier(
        for snapshot: ProcessSnapshot,
        snapshotsByPid: [Int32: ProcessSnapshot]) -> String?
    {
        var nextPid = snapshot.ppid
        var seen: Set<Int32> = [snapshot.pid]

        for _ in 0..<8 {
            guard nextPid > 0,
                  !seen.contains(nextPid),
                  let parent = snapshotsByPid[nextPid] else { return nil }

            if let identifier = ProcessNaming.mcpIdentifier(in: parent.command) {
                return identifier
            }

            if ProcessNaming.playwrightMCPBrowserName(in: parent.command) != nil ||
                parent.command.lowercased().contains("ms-playwright")
            {
                return "Playwright MCP"
            }

            seen.insert(nextPid)
            nextPid = parent.ppid
        }

        return nil
    }
}
