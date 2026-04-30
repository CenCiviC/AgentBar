import AppKit

enum TerminalActivator {
    private static let knownExecutableNames: Set<String> = [
        "terminal", "iterm2", "ghostty", "wezterm-gui", "kitty", "alacritty", "warp",
    ]

    private static let bundleIdentifiers = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    @discardableResult
    static func activateAncestorApp(for pid: Int32, snapshotsByPid: [Int32: ProcessSnapshot]) -> Int32? {
        var nextPid = pid
        var seen: Set<Int32> = []

        for _ in 0..<16 {
            guard !seen.contains(nextPid),
                  let snapshot = snapshotsByPid[nextPid] else { return nil }

            if self.isTerminalApp(snapshot),
               let app = NSRunningApplication(processIdentifier: snapshot.pid),
               app.activate(options: [.activateAllWindows])
            {
                return snapshot.pid
            }

            seen.insert(nextPid)
            nextPid = snapshot.ppid
        }

        return nil
    }

    @discardableResult
    static func activateLikelyTerminalApp() -> Int32? {
        for identifier in self.bundleIdentifiers {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                where app.activate(options: [.activateAllWindows])
            {
                return app.processIdentifier
            }
        }
        return nil
    }

    private static func isTerminalApp(_ snapshot: ProcessSnapshot) -> Bool {
        guard snapshot.command.contains(".app/Contents/MacOS/") else { return false }
        return self.knownExecutableNames.contains(snapshot.executableName.lowercased())
    }
}
