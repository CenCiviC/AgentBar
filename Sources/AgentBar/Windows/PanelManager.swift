import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelManager {
    private(set) var statusItem: NSStatusItem
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(monitor: ProcessMonitor) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.updateButton(count: 0)
        self.buildPanel(monitor: monitor)

        monitor.$processes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in self?.updateButton(count: processes.count) }
            .store(in: &self.cancellables)
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible { self.close() } else { self.show() }
    }

    func show() {
        guard let panel, let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)
        let panelWidth = panel.frame.width
        var originX = screenFrame.midX - panelWidth / 2
        let originY = screenFrame.minY - panel.frame.height - 4

        if let screen = NSScreen.main {
            originX = max(screen.visibleFrame.minX + 4, min(originX, screen.visibleFrame.maxX - panelWidth - 4))
        }

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        self.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if event.window !== panel { self.close() }
        }
    }

    func close() {
        self.panel?.orderOut(nil)
        self.statusItem.button?.layer?.backgroundColor = NSColor.clear.cgColor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Private

    private func buildPanel(monitor: ProcessMonitor) {
        let panelSize = NSSize(width: 560, height: 500)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

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

        panel.contentView = effectView
        self.panel = panel
    }

    private func updateButton(count: Int) {
        guard let button = statusItem.button else { return }
        let symbolName = count == 0 ? "moon.zzz" : "cpu"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentBar")
        image?.isTemplate = true
        button.image = image
        button.title = " \(count)"
        button.imagePosition = .imageLeading
    }
}
