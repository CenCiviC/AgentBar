import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func open() {
        if self.window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false)
            win.title = "Settings"
            win.isReleasedWhenClosed = false
            win.center()
            win.contentView = NSHostingView(rootView: self.settingsContent)
            self.window = win
        }

        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }

    private var settingsContent: some View {
        TabView {
            SettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 340)
    }
}
