import SwiftUI

struct ProcessRow: View {
    let process: AgentProcess
    @EnvironmentObject var monitor: ProcessMonitor
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            self.processInfo
            CopyButton(
                text: self.clipboardText,
                tooltip: "Copy process info\nPaste into an AI assistant to ask for an ETA\nor what it's likely doing.")
            KillButton(
                systemImage: "xmark",
                color: .red,
                tooltip: "Quit process (SIGTERM)\nIf it doesn't exit within 3 seconds,\nyou'll be asked to force kill it.")
            {
                self.monitor.killGracefully(self.process.id, processName: self.process.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(self.hovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { self.hovering = $0 }
        .help(self.rowHelp)
    }

    // MARK: - Subviews

    private var processInfo: some View {
        HStack(alignment: .center, spacing: 10) {
            self.kindBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(self.process.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if self.process.isZombie {
                        Text("ZOMBIE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(3)
                    }
                }
                Text(self.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { self.handleTap() }
    }

    private var kindBadge: some View {
        VStack(spacing: 2) {
            Text(self.process.kind.rawValue)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(self.process.kind.color.opacity(0.18))
                .foregroundStyle(self.process.kind.color)
                .cornerRadius(4)
                .frame(width: 56)
            if let owner = process.ownerKind {
                Text(owner.rawValue)
                    .font(.system(size: 9).bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(owner.color.opacity(0.15))
                    .foregroundStyle(owner.color)
                    .cornerRadius(3)
                    .frame(width: 56)
            }
        }
    }

    // MARK: - Computed

    private var metaLine: String {
        var parts = [
            "PID \(process.id)",
            "\(String(format: "%.1f", self.process.cpu))% CPU",
            "\(String(format: "%.0f", self.process.memMB)) MB",
        ]
        if let loc = process.terminalLocation { parts.append(loc) }
        return parts.joined(separator: " · ")
    }

    private var clipboardText: String {
        """
        Agent: \(self.process.kind.rawValue)
        Name: \(self.process.name)
        PID: \(self.process.id)
        Terminal: \(self.process.terminalLocation ?? "unknown")
        CPU: \(String(format: "%.1f", self.process.cpu))%
        Memory: \(String(format: "%.0f", self.process.memMB)) MB
        Zombie: \(self.process.isZombie ? "yes" : "no")
        Command: \(self.process.command)
        """
    }

    private var rowHelp: String {
        if self.process.kind == .mcp {
            if let ownerKind = process
                .ownerKind { return "Click to focus \(ownerKind.rawValue) terminal\n\(self.process.command)" }
            return self.process.command
        }
        if let loc = process.terminalLocation { return "Click to focus \(loc)\n\(self.process.command)" }
        return "Click to focus terminal\n\(self.process.command)"
    }

    private func handleTap() {
        if self.process.kind == .mcp, let ownerPid = process.ownerPid,
           let owner = monitor.processes.first(where: { $0.id == ownerPid })
        {
            self.monitor.focus(owner)
        } else {
            self.monitor.focus(self.process)
        }
        NotificationCenter.default.post(name: .agentBarClosePanelRequested, object: nil)
    }
}
