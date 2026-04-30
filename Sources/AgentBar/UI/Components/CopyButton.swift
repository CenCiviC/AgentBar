import AppKit
import SwiftUI

struct CopyButton: View {
    let text: String
    let tooltip: String

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button(action: self.copy) {
            Image(systemName: self.copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(self.hovering ? 0.25 : 0.12))
                .foregroundStyle(self.copied ? Color.green : Color.secondary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
        .help(self.tooltip)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self.text, forType: .string)
        self.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.copied = false }
    }
}
