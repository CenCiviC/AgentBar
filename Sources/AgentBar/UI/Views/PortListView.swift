import SwiftUI

struct PortListView: View {
    let ports: [PortInfo]
    let totalPortCount: Int
    let systemPortsHidden: Bool

    var body: some View {
        if self.ports.isEmpty {
            self.emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(self.ports) { port in
                        PortRow(port: port)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No listening ports")
                .foregroundStyle(.secondary)
                .font(.callout)
            if self.systemPortsHidden, self.totalPortCount > self.ports.count {
                Text("(\(self.totalPortCount - self.ports.count) system ports hidden)")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
