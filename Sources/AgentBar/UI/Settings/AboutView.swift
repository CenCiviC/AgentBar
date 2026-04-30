import SwiftUI

struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/CenCiviC/AgentBar")!
    private let releasesURL = URL(string: "https://github.com/CenCiviC/AgentBar/releases")!
    private let email = "rudqls513@gmail.com"

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.55, blue: 1.0),
                                    Color(red: 0.1, green: 0.35, blue: 0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Image(systemName: "cpu")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                Text("AgentBar").font(.title.bold())
                Text("Version \(self.version) (\(self.build))").foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                LinkRow(icon: "chevron.left.forwardslash.chevron.right", label: "GitHub", url: self.githubURL)
                LinkRow(icon: "envelope", label: "Email", url: URL(string: "mailto:\(self.email)")!)
            }
            .padding(.vertical, 16)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button("Check for Updates...") { NSWorkspace.shared.open(self.releasesURL) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Text("© 2026 CenCiviC. MIT License.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(width: 420)
    }
}

private struct LinkRow: View {
    let icon: String
    let label: String
    let url: URL

    var body: some View {
        Link(destination: self.url) {
            HStack(spacing: 8) {
                Image(systemName: self.icon).frame(width: 18)
                Text(self.label)
            }
            .font(.system(size: 13))
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}
