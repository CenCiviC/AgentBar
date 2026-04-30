import Foundation

struct TmuxPane {
    let tty: String
    let sessionName: String
    let windowIndex: String
    let paneIndex: String
    let paneID: String

    var displayName: String {
        "\(self.sessionName):\(self.windowIndex).\(self.paneIndex)"
    }

    var windowTarget: String {
        "\(self.sessionName):\(self.windowIndex)"
    }
}

struct TmuxClient {
    let sessionName: String
    let pid: Int32
}

struct TmuxState {
    var panesByTTY: [String: TmuxPane] = [:]
    var clientsBySession: [String: [TmuxClient]] = [:]
}

private struct TmuxFlashState {
    let token: UUID
    let originalStyle: String?
}

final class TmuxManager {
    private var flashStates: [String: TmuxFlashState] = [:]

    func loadState() -> TmuxState {
        guard let tmux = ShellRunner.executablePath(named: "tmux") else { return TmuxState() }

        let separator = "\u{1F}"
        let panesFormat = ["#{pane_tty}", "#{session_name}", "#{window_index}", "#{pane_index}", "#{pane_id}"]
            .joined(separator: separator)

        var state = TmuxState()
        let panesResult = ShellRunner.run(launchPath: tmux, arguments: ["list-panes", "-a", "-F", panesFormat])
        if panesResult.status == 0 {
            for line in panesResult.output.split(separator: "\n").map(String.init) {
                let fields = line.components(separatedBy: separator)
                guard fields.count >= 5,
                      let tty = ProcessParser.normalizedTTY(fields[0]) else { continue }
                state.panesByTTY[tty] = TmuxPane(
                    tty: tty,
                    sessionName: fields[1],
                    windowIndex: fields[2],
                    paneIndex: fields[3],
                    paneID: fields[4])
            }
        }

        let clientsFormat = ["#{session_name}", "#{client_pid}"].joined(separator: separator)
        let clientsResult = ShellRunner.run(launchPath: tmux, arguments: ["list-clients", "-F", clientsFormat])
        if clientsResult.status == 0 {
            for line in clientsResult.output.split(separator: "\n").map(String.init) {
                let fields = line.components(separatedBy: separator)
                guard fields.count >= 2, let pid = Int32(fields[1]) else { continue }
                let client = TmuxClient(sessionName: fields[0], pid: pid)
                state.clientsBySession[client.sessionName, default: []].append(client)
            }
        }

        return state
    }

    @discardableResult
    func selectPane(_ pane: TmuxPane) -> Bool {
        self.run(arguments: ["select-window", "-t", pane.windowTarget])
        return self.run(arguments: ["select-pane", "-t", pane.paneID])
    }

    func flash(_ pane: TmuxPane) {
        let target = pane.paneID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.applyFlash(target: target)
        }
    }

    // MARK: - Private

    @discardableResult
    private func run(arguments: [String]) -> Bool {
        guard let tmux = ShellRunner.executablePath(named: "tmux") else { return false }
        return ShellRunner.run(launchPath: tmux, arguments: arguments).status == 0
    }

    private func runOutput(arguments: [String]) -> (status: Int32, output: String) {
        guard let tmux = ShellRunner.executablePath(named: "tmux") else { return (-1, "") }
        return ShellRunner.run(launchPath: tmux, arguments: arguments)
    }

    private func applyFlash(target: String) {
        let originalStyle: String?
        if let existing = flashStates[target] {
            originalStyle = existing.originalStyle
        } else {
            let result = self.runOutput(arguments: ["show-option", "-pqv", "-t", target, "window-active-style"])
            let style = result.status == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            originalStyle = style.isEmpty ? nil : style
        }

        let token = UUID()
        self.flashStates[target] = TmuxFlashState(token: token, originalStyle: originalStyle)
        self.run(arguments: [
            "set-option",
            "-p",
            "-t",
            target,
            "window-active-style",
            self.computeFlashStyle(originalStyle: originalStyle),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.flashStates[target]?.token == token else { return }
            let savedStyle = self.flashStates[target]?.originalStyle
            self.flashStates[target] = nil

            if let savedStyle {
                self.run(arguments: ["set-option", "-p", "-t", target, "window-active-style", savedStyle])
            } else {
                self.run(arguments: ["set-option", "-pu", "-t", target, "window-active-style"])
            }
        }
    }

    private func computeFlashStyle(originalStyle: String?) -> String {
        if let style = originalStyle, let lightened = lightenedStyle(style) { return lightened }
        let globalResult = self.runOutput(arguments: ["show-option", "-gqv", "window-style"])
        let globalStyle = globalResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !globalStyle.isEmpty, let lightened = lightenedStyle(globalStyle) { return lightened }
        return "bg=colour240"
    }

    private func lightenedStyle(_ style: String) -> String? {
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
        if lower.hasPrefix("#"), lower.count == 7 { return self.blendHexWithWhite(lower, factor: 0.25) }
        if lower.hasPrefix("colour"), let index = Int(lower.dropFirst(6)) {
            return "colour\(self.lightenColourIndex(index))"
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
        case 0..<8: return index + 8
        case 8..<16: return index
        case 16..<232:
            let i = index - 16
            let b = i % 6, g = (i / 6) % 6, r = i / 36
            return 16 + 36 * min(5, r + 1) + 6 * min(5, g + 1) + min(5, b + 1)
        default: return min(255, index + 4)
        }
    }
}
