import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var monitor: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            kindSummary
            Divider()
            bodyContent
            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AgentBar")
                    .font(.headline)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(12)
    }

    private var kindSummary: some View {
        HStack(spacing: 6) {
            ForEach(AgentKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                let count = monitor.count(of: kind)
                HStack(spacing: 4) {
                    Circle().fill(kind.color).frame(width: 7, height: 7)
                    Text(kind.rawValue)
                        .font(.caption)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count > 0 ? .primary : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(count > 0 ? kind.color.opacity(0.12) : Color.clear)
                .cornerRadius(6)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if monitor.processes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No agent processes running")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(monitor.processes) { proc in
                        ProcessRow(process: proc)
                            .environmentObject(monitor)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var footer: some View {
        HStack {
            Menu {
                Section("All") {
                    Button("Terminate All (SIGTERM)") { monitor.killAll(force: false) }
                    Button("Force Kill All (SIGKILL)") { monitor.killAll(force: true) }
                }
                Section("By Agent") {
                    ForEach(AgentKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                        let count = monitor.count(of: kind)
                        Button("Terminate all \(kind.rawValue) (\(count))") {
                            monitor.killAll(of: kind, force: false)
                        }
                        .disabled(count == 0)
                    }
                }
            } label: {
                Text("Kill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(monitor.processes.isEmpty)

            Spacer()

            Button("Quit AgentBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
    }

    private var summaryLine: String {
        if monitor.processes.isEmpty {
            return "Nothing to clean up"
        }
        let cpu = String(format: "%.1f", monitor.totalCPU)
        let mem = String(format: "%.0f", monitor.totalMemMB)
        return "\(monitor.processes.count) processes · \(cpu)% CPU · \(mem) MB"
    }
}

struct ProcessRow: View {
    let process: AgentProcess
    @EnvironmentObject var monitor: ProcessMonitor
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            kindBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if process.isZombie {
                        Text("ZOMBIE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(3)
                    }
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: clipboardText, tooltip: "Copy process info\nPaste into an AI assistant to ask for an ETA\nor what it's likely doing.")
            KillButton(
                label: "Quit",
                systemImage: "door.left.hand.open",
                color: .orange,
                tooltip: "Graceful quit (SIGTERM)\nProcess can save state and clean up before exiting.\nTry this first."
            ) {
                monitor.kill(process.id, force: false)
            }
            KillButton(
                label: "Force",
                systemImage: "bolt.fill",
                color: .red,
                tooltip: "Force kill (SIGKILL)\nKilled instantly with no cleanup. Possible data loss.\nUse only if Quit doesn't work."
            ) {
                monitor.kill(process.id, force: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering = $0 }
        .help(process.command)
    }

    private var kindBadge: some View {
        Text(process.kind.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(process.kind.color.opacity(0.18))
            .foregroundStyle(process.kind.color)
            .cornerRadius(4)
            .frame(width: 56)
    }

    private var metaLine: String {
        let cpu = String(format: "%.1f", process.cpu)
        let mem = String(format: "%.0f", process.memMB)
        return "PID \(process.id) · \(cpu)% CPU · \(mem) MB"
    }

    private var clipboardText: String {
        let cpu = String(format: "%.1f", process.cpu)
        let mem = String(format: "%.0f", process.memMB)
        return """
        Agent: \(process.kind.rawValue)
        Name: \(process.name)
        PID: \(process.id)
        CPU: \(cpu)%
        Memory: \(mem) MB
        Zombie: \(process.isZombie ? "yes" : "no")
        Command: \(process.command)
        """
    }
}

struct CopyButton: View {
    let text: String
    let tooltip: String

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(hovering ? 0.25 : 0.12))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            copied = false
        }
    }
}

struct KillButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let tooltip: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(hovering ? 0.30 : 0.16))
            .foregroundStyle(color)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
    }
}
