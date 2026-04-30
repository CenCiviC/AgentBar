import AppKit
import Combine
import Foundation

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var processes: [AgentProcess] = []
    @Published var ports: [PortInfo] = []
    @Published var lastRefresh: Date = .now

    private var timer: Timer?
    private var latestSnapshotsByPid: [Int32: ProcessSnapshot] = [:]
    private var latestTmuxState = TmuxState()
    private let tmux = TmuxManager()

    init() {
        self.refresh()
        self.timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let result = ShellRunner.run(
            launchPath: "/bin/ps",
            // -ww disables column truncation so the command field is never clipped.
            arguments: ["-axww", "-o", "pid=,ppid=,tty=,pcpu=,rss=,stat=,command="])
        guard result.status == 0 else { return }

        let myPid = ProcessInfo.processInfo.processIdentifier
        let snapshots = ProcessParser.parse(psOutput: result.output)
        let snapshotsByPid = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) })
        let tmuxState = self.tmux.loadState()
        self.latestSnapshotsByPid = snapshotsByPid
        self.latestTmuxState = tmuxState

        var found: [AgentProcess] = []
        for snapshot in snapshots {
            guard snapshot.pid != myPid else { continue }
            guard let kind = ProcessParser.matchKind(
                argv0Basename: snapshot.executableName.lowercased(),
                command: snapshot.command.lowercased()) else { continue }

            let displayName = ProcessNaming.friendlyName(kind: kind, snapshot: snapshot, snapshotsByPid: snapshotsByPid)
            let owner = kind == .mcp ? ProcessHierarchy.agentOwner(for: snapshot, snapshotsByPid: snapshotsByPid) : nil
            found.append(AgentProcess(
                id: snapshot.pid,
                kind: kind,
                ownerKind: owner?.kind,
                ownerPid: owner?.pid,
                name: displayName,
                tty: snapshot.tty,
                terminalLocation: ProcessNaming.terminalLocation(for: snapshot, panesByTTY: tmuxState.panesByTTY),
                command: snapshot.command,
                cpu: snapshot.cpu,
                memMB: snapshot.rss / 1024.0,
                isZombie: snapshot.stat.contains("Z")))
        }

        self.processes = found
        self.lastRefresh = .now
        self.ports = PortParser.fetchPorts(
            snapshotsByPid: snapshotsByPid,
            agentByPid: Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0.kind) }))
    }

    // MARK: - Kill

    func kill(_ pid: Int32, force: Bool = false) {
        _ = ShellRunner.run(launchPath: "/bin/kill", arguments: [force ? "-9" : "-15", String(pid)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func killGracefully(_ pid: Int32, processName: String) {
        self.kill(pid, force: false)
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
        for proc in self.processes {
            self.kill(proc.id, force: force)
        }
    }

    func killAll(of kind: AgentKind, force: Bool = false) {
        for proc in self.processes where proc.kind == kind {
            kill(proc.id, force: force)
        }
    }

    // MARK: - Focus

    func focus(_ process: AgentProcess) {
        if let tty = process.tty,
           let pane = latestTmuxState.panesByTTY[tty] ?? tmux.loadState().panesByTTY[tty]
        {
            self.tmux.selectPane(pane)
            _ = self.activateTmuxClient(for: pane)
                ?? TerminalActivator.activateAncestorApp(for: process.id, snapshotsByPid: self.latestSnapshotsByPid)
                ?? TerminalActivator.activateLikelyTerminalApp()
            self.tmux.flash(pane)
            return
        }
        _ = TerminalActivator.activateAncestorApp(for: process.id, snapshotsByPid: self.latestSnapshotsByPid)
            ?? TerminalActivator.activateLikelyTerminalApp()
    }

    // MARK: - Stats

    var totalCPU: Double {
        self.processes.reduce(0) { $0 + $1.cpu }
    }

    var totalMemMB: Double {
        self.processes.reduce(0) { $0 + $1.memMB }
    }

    func count(of kind: AgentKind) -> Int {
        self.processes.count(where: { $0.kind == kind })
    }

    // MARK: - Private

    private func activateTmuxClient(for pane: TmuxPane) -> Int32? {
        let clients = self.latestTmuxState.clientsBySession[pane.sessionName]
            ?? self.tmux.loadState().clientsBySession[pane.sessionName]
            ?? []
        for client in clients {
            if let pid = TerminalActivator.activateAncestorApp(for: client.pid, snapshotsByPid: latestSnapshotsByPid) {
                return pid
            }
        }
        return TerminalActivator.activateLikelyTerminalApp()
    }
}
