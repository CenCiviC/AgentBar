import SwiftUI

struct SettingsView: View {
    @AppStorage("sortOrder") private var sortOrderRaw: String = ProcessSortOrder.cpu.rawValue
    @AppStorage("hideSystemPorts") private var hideSystemPorts: Bool = true

    private var sortOrder: Binding<ProcessSortOrder> {
        Binding(
            get: { ProcessSortOrder(rawValue: sortOrderRaw) ?? .cpu },
            set: { sortOrderRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionHeader("DISPLAY")

                SettingsPickerRow(
                    title: "Sort order",
                    description: "How agent processes are ordered in the list.",
                    selection: sortOrder,
                    options: [
                        (ProcessSortOrder.cpu, "CPU Usage"),
                        (ProcessSortOrder.recent, "Most Recent"),
                        (ProcessSortOrder.tmux, "Tmux Window / Pane"),
                    ]
                )

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SettingsSectionHeader("PORTS")

                SettingsToggleRow(
                    title: "Hide system ports",
                    description: "Filter out known macOS system daemons (sshd, mDNSResponder, sharingd, etc.) from the Ports tab.",
                    isOn: $hideSystemPorts
                )

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 420)
    }
}

struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .fixedSize()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    let description: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
