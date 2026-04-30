import SwiftUI
import AppKit
import Combine

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var monitor: ProcessMonitor?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let m = ProcessMonitor()
        self.monitor = m

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        self.statusItem = item
        updateButton(count: 0)

        let pop = NSPopover()
        pop.behavior = .transient
        pop.delegate = self
        pop.contentSize = NSSize(width: 460, height: 500)
        pop.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(m)
        )
        self.popover = pop

        m.$processes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                self?.updateButton(count: processes.count)
            }
            .store(in: &cancellables)
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

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let pop = popover else { return }
        if pop.isShown {
            pop.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
