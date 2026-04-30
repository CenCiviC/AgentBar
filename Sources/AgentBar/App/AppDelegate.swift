import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var processMonitor: ProcessMonitor?
    private var panelManager: PanelManager?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let monitor = ProcessMonitor()
        self.processMonitor = monitor

        let panel = PanelManager(monitor: monitor)
        panel.statusItem.button?.action = #selector(self.togglePanel(_:))
        panel.statusItem.button?.target = self
        self.panelManager = panel

        self.settingsController = SettingsWindowController()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.closePanelFromNotification(_:)),
            name: .agentBarClosePanelRequested,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.openSettings(_:)),
            name: .agentBarOpenSettingsRequested,
            object: nil)
    }

    @objc func togglePanel(_ sender: AnyObject?) {
        self.panelManager?.toggle()
    }

    @objc private func closePanelFromNotification(_ notification: Notification) {
        self.panelManager?.close()
    }

    @objc private func openSettings(_ notification: Notification) {
        self.panelManager?.close()
        self.settingsController?.open()
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        self.settingsController?.open()
    }
}
