import SwiftUI

enum AppTab {
    case processes, ports
}

struct ContentView: View {
    @EnvironmentObject var monitor: ProcessMonitor
    @AppStorage("hiddenKinds") private var hiddenKindsRaw: String = ""
    @AppStorage("sortOrder") private var sortOrderRaw: String = ProcessSortOrder.cpu.rawValue
    @AppStorage("hideSystemPorts") private var hideSystemPorts: Bool = true
    @State private var selectedTab: AppTab = .processes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            Divider()
            self.tabBar
            Divider()
            switch self.selectedTab {
            case .processes:
                self.kindSummary
                Divider()
                ProcessListView(processes: self.visibleProcesses, sortOrder: self.sortOrder)
            case .ports:
                PortListView(
                    ports: self.filteredPorts,
                    totalPortCount: self.monitor.ports.count,
                    systemPortsHidden: self.hideSystemPorts)
            }
            Divider()
            self.footer
        }
        .frame(width: 560, height: 500)
        .background(.clear)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AgentBar").font(.headline)
                Text(self.summaryLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if self.selectedTab == .processes {
                Button { self.toggleSortOrder() } label: { Image(systemName: self.sortOrderIcon) }
                    .buttonStyle(.borderless)
                    .help(self.sortOrderHelp)
            }
            Button { self.monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
        }
        .padding(12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(title: "Agents", isSelected: self.selectedTab == .processes) { self.selectedTab = .processes }
            TabBarButton(title: "Ports", isSelected: self.selectedTab == .ports) { self.selectedTab = .ports }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var kindSummary: some View {
        HStack(spacing: 6) {
            ForEach(AgentKind.allCases.filter { $0 != .other && self.monitor.count(of: $0) > 0 }, id: \.self) { kind in
                let count = self.monitor.count(of: kind)
                let hidden = self.hiddenKinds.contains(kind)
                Button { self.toggleHidden(kind) } label: {
                    HStack(spacing: 4) {
                        Circle().fill(kind.color).frame(width: 7, height: 7)
                        Text(kind.rawValue).font(.caption)
                        Text("\(count)").font(.caption.monospacedDigit())
                            .foregroundStyle(count > 0 ? .primary : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hidden ? Color.clear : (count > 0 ? kind.color.opacity(0.12) : Color.clear))
                    .cornerRadius(6)
                    .opacity(hidden ? 0.4 : 1.0)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(hidden ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(hidden ? "Show \(kind.rawValue) processes" : "Hide \(kind.rawValue) processes")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Menu {
                Section("All") {
                    Button("Terminate All (SIGTERM)") { self.monitor.killAll(force: false) }
                    Button("Force Kill All (SIGKILL)") { self.monitor.killAll(force: true) }
                }
                Section("By Agent") {
                    ForEach(AgentKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                        let count = self.monitor.count(of: kind)
                        Button("Terminate all \(kind.rawValue) (\(count))") {
                            self.monitor.killAll(of: kind, force: false)
                        }
                        .disabled(count == 0)
                    }
                }
            } label: { Text("Kill") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(self.monitor.processes.isEmpty)

            Spacer()

            Button("Settings...") {
                NotificationCenter.default.post(name: .agentBarOpenSettingsRequested, object: nil)
            }
            .buttonStyle(.borderless)

            Button("Quit AgentBar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
    }

    // MARK: - Computed

    private var sortOrder: ProcessSortOrder {
        ProcessSortOrder(rawValue: self.sortOrderRaw) ?? .cpu
    }

    private var hiddenKinds: Set<AgentKind> {
        Set(self.hiddenKindsRaw.split(separator: ",").compactMap { AgentKind(rawValue: String($0)) })
    }

    private var visibleProcesses: [AgentProcess] {
        self.monitor.processes.filter { !self.hiddenKinds.contains($0.kind) }
    }

    private var filteredPorts: [PortInfo] {
        guard self.hideSystemPorts else { return self.monitor.ports }
        return self.monitor.ports.filter { !macOSSystemProcessNames.contains($0.processName) }
    }

    private var summaryLine: String {
        guard !self.monitor.processes.isEmpty else { return "Nothing to clean up" }
        let cpu = String(format: "%.1f", monitor.totalCPU)
        let mem = String(format: "%.0f", monitor.totalMemMB)
        let total = self.monitor.processes.count
        let visible = self.visibleProcesses.count
        let countText = visible < total ? "\(visible)/\(total) processes" : "\(total) processes"
        return "\(countText) · \(cpu)% CPU · \(mem) MB"
    }

    private var sortOrderIcon: String {
        switch self.sortOrder {
        case .cpu: "chart.bar.fill"
        case .recent: "clock.fill"
        case .tmux: "rectangle.split.2x1.fill"
        }
    }

    private var sortOrderHelp: String {
        switch self.sortOrder {
        case .cpu: "Sorted by CPU — click for most recent"
        case .recent: "Sorted by most recent — click for tmux order"
        case .tmux: "Sorted by tmux window/pane — click for CPU"
        }
    }

    // MARK: - Actions

    private func toggleHidden(_ kind: AgentKind) {
        var kinds = self.hiddenKinds
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
        self.hiddenKindsRaw = kinds.map(\.rawValue).joined(separator: ",")
    }

    private func toggleSortOrder() {
        switch self.sortOrder {
        case .cpu: self.sortOrderRaw = ProcessSortOrder.recent.rawValue
        case .recent: self.sortOrderRaw = ProcessSortOrder.tmux.rawValue
        case .tmux: self.sortOrderRaw = ProcessSortOrder.cpu.rawValue
        }
    }
}
