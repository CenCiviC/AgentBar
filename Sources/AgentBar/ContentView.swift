import SwiftUI
import AppKit

enum AppTab {
    case processes, ports
}

struct ContentView: View {
    @EnvironmentObject var monitor: ProcessMonitor
    @AppStorage("hiddenKinds") private var hiddenKindsRaw: String = ""
    @AppStorage("sortOrder") private var sortOrderRaw: String = ProcessSortOrder.cpu.rawValue
    @State private var selectedTab: AppTab = .processes

    private var sortOrder: ProcessSortOrder {
        ProcessSortOrder(rawValue: sortOrderRaw) ?? .cpu
    }

    private var hiddenKinds: Set<AgentKind> {
        Set(hiddenKindsRaw.split(separator: ",").compactMap { AgentKind(rawValue: String($0)) })
    }

    private func toggleHidden(_ kind: AgentKind) {
        var kinds = hiddenKinds
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
        hiddenKindsRaw = kinds.map(\.rawValue).joined(separator: ",")
    }

    private func toggleSortOrder() {
        switch sortOrder {
        case .cpu:    sortOrderRaw = ProcessSortOrder.recent.rawValue
        case .recent: sortOrderRaw = ProcessSortOrder.tmux.rawValue
        case .tmux:   sortOrderRaw = ProcessSortOrder.cpu.rawValue
        }
    }

    private var sortOrderIcon: String {
        switch sortOrder {
        case .cpu:    return "chart.bar.fill"
        case .recent: return "clock.fill"
        case .tmux:   return "rectangle.split.2x1.fill"
        }
    }

    private var sortOrderHelp: String {
        switch sortOrder {
        case .cpu:    return "Sorted by CPU — click for most recent"
        case .recent: return "Sorted by most recent — click for tmux order"
        case .tmux:   return "Sorted by tmux window/pane — click for CPU"
        }
    }

    private var visibleProcesses: [AgentProcess] {
        let filtered = monitor.processes.filter { !hiddenKinds.contains($0.kind) }
        switch sortOrder {
        case .cpu:
            return filtered.sorted { $0.cpu > $1.cpu }
        case .recent:
            return filtered.sorted { $0.id > $1.id }
        case .tmux:
            return filtered.sorted {
                let a = tmuxSortKey(for: $0)
                let b = tmuxSortKey(for: $1)
                if a.0 != b.0 { return a.0 < b.0 }
                if a.1 != b.1 { return a.1 < b.1 }
                return a.2 < b.2
            }
        }
    }

    private func tmuxSortKey(for process: AgentProcess) -> (String, Int, Int) {
        guard let loc = process.terminalLocation, loc.hasPrefix("tmux ") else {
            return ("\u{FFFF}", Int.max, Int.max)
        }
        let body = String(loc.dropFirst(5))
        let colonParts = body.split(separator: ":", maxSplits: 1)
        guard colonParts.count == 2 else { return (body, Int.max, Int.max) }
        let session = String(colonParts[0])
        let dotParts = colonParts[1].split(separator: ".")
        guard dotParts.count >= 2,
              let window = Int(dotParts[0]),
              let pane   = Int(dotParts[1]) else { return (session, Int.max, Int.max) }
        return (session, window, pane)
    }

    private func tmuxWindowKey(for process: AgentProcess) -> String {
        guard let loc = process.terminalLocation, loc.hasPrefix("tmux ") else { return "Other" }
        let body = String(loc.dropFirst(5))
        if let lastDot = body.lastIndex(of: ".") { return String(body[..<lastDot]) }
        return body
    }

    private struct TmuxGroup: Identifiable {
        let window: String
        var processes: [AgentProcess]
        var id: String { window }
    }

    private var tmuxGroups: [TmuxGroup] {
        var groups: [TmuxGroup] = []
        var index: [String: Int] = [:]
        for proc in visibleProcesses {
            let key = tmuxWindowKey(for: proc)
            if let i = index[key] {
                groups[i].processes.append(proc)
            } else {
                index[key] = groups.count
                groups.append(TmuxGroup(window: key, processes: [proc]))
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            switch selectedTab {
            case .processes:
                kindSummary
                Divider()
                processesContent
            case .ports:
                portsContent
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 500)
        .background(.clear)
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
            if selectedTab == .processes {
                Button { toggleSortOrder() } label: {
                    Image(systemName: sortOrderIcon)
                }
                .buttonStyle(.borderless)
                .help(sortOrderHelp)
            }
            Button { monitor.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(12)
    }

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            Text("Agents \(monitor.processes.count)").tag(AppTab.processes)
            Text("Ports \(monitor.ports.count)").tag(AppTab.ports)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var kindSummary: some View {
        HStack(spacing: 6) {
            ForEach(AgentKind.allCases.filter { $0 != .other && monitor.count(of: $0) > 0 }, id: \.self) { kind in
                let count = monitor.count(of: kind)
                let hidden = hiddenKinds.contains(kind)
                Button { toggleHidden(kind) } label: {
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
                    .background(hidden ? Color.clear : (count > 0 ? kind.color.opacity(0.12) : Color.clear))
                    .cornerRadius(6)
                    .opacity(hidden ? 0.4 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hidden ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(hidden ? "Show \(kind.rawValue) processes" : "Hide \(kind.rawValue) processes")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var processesContent: some View {
        if visibleProcesses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: monitor.processes.isEmpty ? "moon.zzz" : "eye.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(monitor.processes.isEmpty ? "No agent processes running" : "All processes are hidden")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if !monitor.processes.isEmpty {
                    Text("Click a kind badge above to show them")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sortOrder == .tmux {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(tmuxGroups) { group in
                        Section {
                            ForEach(group.processes) { proc in
                                ProcessRow(process: proc)
                                    .environmentObject(monitor)
                                Divider()
                            }
                        } header: {
                            HStack {
                                Text(group.window)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("(\(group.processes.count))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.regularMaterial)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleProcesses) { proc in
                        ProcessRow(process: proc)
                            .environmentObject(monitor)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var portsContent: some View {
        if monitor.ports.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "network.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No listening ports")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(monitor.ports) { port in
                        PortRow(port: port)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
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

            Button("Settings...") {
                NotificationCenter.default.post(name: .agentBarOpenSettingsRequested, object: nil)
            }
            .buttonStyle(.borderless)

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
        let total = monitor.processes.count
        let visible = visibleProcesses.count
        let countText = visible < total ? "\(visible)/\(total) processes" : "\(total) processes"
        return "\(countText) · \(cpu)% CPU · \(mem) MB"
    }
}

struct ProcessRow: View {
    let process: AgentProcess
    @EnvironmentObject var monitor: ProcessMonitor
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            processInfo
            CopyButton(text: clipboardText, tooltip: "Copy process info\nPaste into an AI assistant to ask for an ETA\nor what it's likely doing.")
            KillButton(
                systemImage: "xmark",
                color: .red,
                tooltip: "Quit process (SIGTERM)\nIf it doesn't exit within 3 seconds,\nyou'll be asked to force kill it."
            ) {
                monitor.killGracefully(process.id, processName: process.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering = $0 }
        .help(rowHelp)
    }

    private var processInfo: some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if process.kind == .mcp {
                if let ownerPid = process.ownerPid,
                   let owner = monitor.processes.first(where: { $0.id == ownerPid }) {
                    monitor.focus(owner)
                    NotificationCenter.default.post(name: .agentBarClosePanelRequested, object: nil)
                }
            } else {
                monitor.focus(process)
                NotificationCenter.default.post(name: .agentBarClosePanelRequested, object: nil)
            }
        }
    }

    private var kindBadge: some View {
        VStack(spacing: 2) {
            Text(process.kind.rawValue)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(process.kind.color.opacity(0.18))
                .foregroundStyle(process.kind.color)
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

    private var metaLine: String {
        let cpu = String(format: "%.1f", process.cpu)
        let mem = String(format: "%.0f", process.memMB)
        var parts = ["PID \(process.id)", "\(cpu)% CPU", "\(mem) MB"]
        if let terminalLocation = process.terminalLocation {
            parts.append(terminalLocation)
        }
        return parts.joined(separator: " · ")
    }

    private var clipboardText: String {
        let cpu = String(format: "%.1f", process.cpu)
        let mem = String(format: "%.0f", process.memMB)
        let terminal = process.terminalLocation ?? "unknown"
        return """
        Agent: \(process.kind.rawValue)
        Name: \(process.name)
        PID: \(process.id)
        Terminal: \(terminal)
        CPU: \(cpu)%
        Memory: \(mem) MB
        Zombie: \(process.isZombie ? "yes" : "no")
        Command: \(process.command)
        """
    }

    private var rowHelp: String {
        if process.kind == .mcp {
            if let ownerKind = process.ownerKind {
                return "Click to focus \(ownerKind.rawValue) terminal\n\(process.command)"
            }
            return process.command
        }
        if let terminalLocation = process.terminalLocation {
            return "Click to focus \(terminalLocation)\n\(process.command)"
        }
        return "Click to focus terminal\n\(process.command)"
    }
}

struct PortRow: View {
    let port: PortInfo

    var body: some View {
        HStack(spacing: 8) {
            Text("\(port.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .trailing)
            Text(port.processName)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            if let kind = port.agentKind {
                Text(kind.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(kind.color.opacity(0.18))
                    .foregroundStyle(kind.color)
                    .cornerRadius(4)
            }
            Spacer()
            Text("PID \(port.pid)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(port.address == "*" ? "all" : port.address)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
    let systemImage: String
    let color: Color
    let tooltip: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 22, height: 22)
                .background(color.opacity(hovering ? 0.30 : 0.16))
                .foregroundStyle(color)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
    }
}
