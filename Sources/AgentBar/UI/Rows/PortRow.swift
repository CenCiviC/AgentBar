import SwiftUI

struct PortRow: View {
    let port: PortInfo

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
            Text("PID \(self.port.pid)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(self.port.address == "*" ? "all" : self.port.address)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
