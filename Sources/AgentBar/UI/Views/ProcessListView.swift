import SwiftUI

struct ProcessListView: View {
    @EnvironmentObject var monitor: ProcessMonitor
    let processes: [AgentProcess]
    let sortOrder: ProcessSortOrder

    var body: some View {
        if self.processes.isEmpty {
            self.emptyState
        } else if self.sortOrder == .tmux {
            self.groupedList
        } else {
            self.flatList
        }
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: self.monitor.processes.isEmpty ? "moon.zzz" : "eye.slash")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(self.monitor.processes.isEmpty ? "No agent processes running" : "All processes are hidden")
                .foregroundStyle(.secondary)
                .font(.callout)
            if !self.monitor.processes.isEmpty {
                Text("Click a kind badge above to show them")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(self.tmuxGroups) { group in
                    Section {
                        ForEach(group.processes) { proc in
                            ProcessRow(process: proc).environmentObject(self.monitor)
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
    }

    private var flatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(self.sortedProcesses) { proc in
                    ProcessRow(process: proc).environmentObject(self.monitor)
                    Divider()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Sorting & Grouping

    private var sortedProcesses: [AgentProcess] {
        switch self.sortOrder {
        case .cpu: self.processes.sorted { $0.cpu > $1.cpu }
        case .recent: self.processes.sorted { $0.id > $1.id }
        case .tmux: self.processes.sorted { lhs, rhs in
                let lhsKey = self.tmuxSortKey(for: lhs)
                let rhsKey = self.tmuxSortKey(for: rhs)
                if lhsKey.0 != rhsKey.0 { return lhsKey.0 < rhsKey.0 }
                if lhsKey.1 != rhsKey.1 { return lhsKey.1 < rhsKey.1 }
                return lhsKey.2 < rhsKey.2
            }
        }
    }

    private struct TmuxGroup: Identifiable {
        let window: String
        var processes: [AgentProcess]
        var id: String {
            self.window
        }
    }

    private var tmuxGroups: [TmuxGroup] {
        var groups: [TmuxGroup] = []
        var index: [String: Int] = [:]
        for proc in self.sortedProcesses {
            let key = self.tmuxWindowKey(for: proc)
            if let idx = index[key] {
                groups[idx].processes.append(proc)
            } else {
                index[key] = groups.count
                groups.append(TmuxGroup(window: key, processes: [proc]))
            }
        }
        return groups
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
              let pane = Int(dotParts[1]) else { return (session, Int.max, Int.max) }
        return (session, window, pane)
    }

    private func tmuxWindowKey(for process: AgentProcess) -> String {
        guard let loc = process.terminalLocation, loc.hasPrefix("tmux ") else { return "Other" }
        let body = String(loc.dropFirst(5))
        if let lastDot = body.lastIndex(of: ".") { return String(body[..<lastDot]) }
        return body
    }
}
