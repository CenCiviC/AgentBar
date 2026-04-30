import SwiftUI

enum AgentKind: String, CaseIterable, Hashable {
    case claude = "Claude"
    case codex = "Codex"
    case gemini = "Gemini"
    case mcp = "MCP"
    case other = "AI"

    var color: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .gemini: .blue
        case .mcp: .purple
        case .other: .gray
        }
    }

    /// Strict matching rules so we don't false-positive on apps like
    /// /Applications/CodexBar.app whose names merely *contain* "codex".
    var rules: MatchRules {
        switch self {
        case .claude:
            MatchRules(
                basenames: ["claude", "claude-code"],
                commandSubstrings: ["@anthropic-ai/claude-code", "anthropic-ai/claude"])
        case .codex:
            MatchRules(
                basenames: ["codex"],
                commandSubstrings: ["@openai/codex", "openai/codex"])
        case .gemini:
            MatchRules(
                basenames: ["gemini", "gemini-cli"],
                commandSubstrings: ["@google/gemini", "google/gemini-cli"])
        case .mcp:
            MatchRules(
                basenames: [],
                commandSubstrings: ["mcp-server", "@modelcontextprotocol", "mcp-"])
        case .other:
            MatchRules(basenames: [], commandSubstrings: [])
        }
    }
}

struct MatchRules {
    let basenames: [String]
    let commandSubstrings: [String]
}
