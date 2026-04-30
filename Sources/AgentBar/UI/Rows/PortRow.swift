import SwiftUI

struct PortRow: View {
    let port: PortInfo
    @EnvironmentObject var monitor: ProcessMonitor
    @State private var hovering = false
    @State private var showSystemKillConfirmation = false

    private var isSystemProcess: Bool {
        macOSSystemProcessNames.contains(self.port.processName) || self.port.port < 1024
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(self.port.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .trailing)
            Text(self.port.processName)
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
            ZStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    Text("PID \(self.port.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(self.port.address == "*" ? "all" : self.port.address)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(width: 70, alignment: .trailing)
                }
                .opacity(self.hovering ? 0 : 1)

                KillButton(
                    systemImage: "xmark",
                    color: .red,
                    tooltip: "Kill process on port \(self.port.port) (SIGTERM)\nPID \(self.port.pid) · \(self.port.processName)")
                {
                    if self.isSystemProcess {
                        self.showSystemKillConfirmation = true
                    } else {
                        self.monitor.killGracefully(self.port.pid, processName: self.port.processName)
                    }
                }
                .opacity(self.hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(self.hovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { self.hovering = $0 }
        .alert("Kill System Process?", isPresented: self.$showSystemKillConfirmation) {
            Button("Kill", role: .destructive) {
                self.monitor.killGracefully(self.port.pid, processName: self.port.processName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\"\(self.port.processName)\" on port \(self.port.port) appears to be a system process. " +
                "Killing it may cause instability or loss of system functionality. Are you sure?")
        }
    }
}
