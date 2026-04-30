import AppKit
import SwiftUI

extension Notification.Name {
    static let agentBarClosePanelRequested = Notification.Name("AgentBarClosePanelRequested")
    static let agentBarOpenSettingsRequested = Notification.Name("AgentBarOpenSettingsRequested")
}

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings...") {
                        NotificationCenter.default.post(name: .agentBarOpenSettingsRequested, object: nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
