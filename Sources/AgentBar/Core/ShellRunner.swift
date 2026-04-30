import Foundation

enum ShellRunner {
    static func run(launchPath: String, arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return (-1, "")
        }

        // Drain the pipe BEFORE waiting; otherwise a process blocks once its
        // ~64KB stdout buffer fills, causing waitUntilExit to deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func executablePath(named name: String) -> String? {
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? fallbackPath
        for directory in envPath.split(separator: ":").map(String.init) {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        for directory in fallbackPath.split(separator: ":").map(String.init) {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
