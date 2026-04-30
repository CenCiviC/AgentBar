import SwiftUI

struct SettingsView: View {
    @AppStorage("sortOrder") private var sortOrderRaw: String = ProcessSortOrder.cpu.rawValue
    @AppStorage("hideSystemPorts") private var hideSystemPorts: Bool = true

    private var sortOrder: Binding<ProcessSortOrder> {
        Binding(
            get: { ProcessSortOrder(rawValue: self.sortOrderRaw) ?? .cpu },
            set: { self.sortOrderRaw = $0.rawValue })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionHeader("DISPLAY")

                SettingsPickerRow(
                    title: "Sort order",
                    description: "How agent processes are ordered in the list.",
                    selection: self.sortOrder,
                    options: [
                        (ProcessSortOrder.cpu, "CPU Usage"),
                        (ProcessSortOrder.recent, "Most Recent"),
                        (ProcessSortOrder.tmux, "Tmux Window / Pane"),
                    ])

                Divider().padding(.horizontal, 20).padding(.top, 8)

                SettingsSectionHeader("PORTS")

                SettingsToggleRow(
                    title: "Hide system ports",
                    description: "Filter out known macOS system daemons (sshd, mDNSResponder, sharingd, etc.) from the Ports tab.",
                    isOn: self.$hideSystemPorts)

                Divider().padding(.horizontal, 20).padding(.top, 8)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 420)
    }
}
