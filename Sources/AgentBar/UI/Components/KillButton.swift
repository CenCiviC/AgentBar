import SwiftUI

struct KillButton: View {
    let systemImage: String
    let color: Color
    let tooltip: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.caption)
                .frame(width: 22, height: 22)
                .background(self.color.opacity(self.hovering ? 0.30 : 0.16))
                .foregroundStyle(self.color)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
        .help(self.tooltip)
    }
}
