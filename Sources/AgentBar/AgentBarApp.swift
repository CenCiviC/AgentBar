import SwiftUI
import AppKit
import Combine

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var processMonitor: ProcessMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let m = ProcessMonitor()
        self.processMonitor = m

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(togglePanel(_:))
        item.button?.target = self
        self.statusItem = item
        updateButton(count: 0)

        buildPanel(monitor: m)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePanelFromNotification(_:)),
            name: .agentBarClosePanelRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings(_:)),
            name: .agentBarOpenSettingsRequested,
            object: nil
        )

        m.$processes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                self?.updateButton(count: processes.count)
            }
            .store(in: &cancellables)
    }

    private func buildPanel(monitor: ProcessMonitor) {
        let panelSize = NSSize(width: 560, height: 500)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .menu
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: ContentView().environmentObject(monitor))
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        effectView.addSubview(hostingView)

        p.contentView = effectView
        self.panel = p
    }

    @objc private func openSettings(_ notification: Notification) {
        closePanel()

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.center()

            let content = TabView {
                SettingsView()
                    .tabItem { Label("General", systemImage: "gear") }
                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            .frame(width: 420, height: 340)

            window.contentView = NSHostingView(rootView: content)
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateButton(count: Int) {
        guard let button = statusItem?.button else { return }
        let symbolName = count == 0 ? "moon.zzz" : "cpu"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentBar")
        image?.isTemplate = true
        button.image = image
        button.title = " \(count)"
        button.imagePosition = .imageLeading
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        guard let panel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        let panelWidth = panel.frame.width
        var x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY - panel.frame.height - 4

        if let screen = NSScreen.main {
            x = max(screen.visibleFrame.minX + 4,
                    min(x, screen.visibleFrame.maxX - panelWidth - 4))
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if event.window !== panel {
                self.closePanel()
            }
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        statusItem?.button?.layer?.backgroundColor = NSColor.clear.cgColor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc private func closePanelFromNotification(_ notification: Notification) {
        closePanel()
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        openSettings(Notification(name: .agentBarOpenSettingsRequested))
    }
}
