import Foundation

enum PortParser {
    static func fetchPorts(
        snapshotsByPid: [Int32: ProcessSnapshot],
        agentByPid: [Int32: AgentKind]) -> [PortInfo]
    {
        let result = ShellRunner.run(
            launchPath: "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-F", "pcn"])
        guard result.status == 0 else { return [] }

        var seen = Set<String>()
        var found: [PortInfo] = []
        var currentPid: Int32?
        var currentCommand: String?

        for line in result.output.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("p"), let pid = Int32(s.dropFirst()) {
                currentPid = pid
                currentCommand = nil
            } else if s.hasPrefix("c") {
                currentCommand = String(s.dropFirst())
            } else if s.hasPrefix("n"), let pid = currentPid {
                let name = String(s.dropFirst())
                guard let colonIdx = name.lastIndex(of: ":"),
                      let port = Int(name[name.index(after: colonIdx)...]),
                      port > 0 else { continue }
                let address = String(name[..<colonIdx])
                let key = "\(pid):\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let displayName: String = if let snapshot = snapshotsByPid[pid] {
                    ProcessNaming.friendlyName(executableName: snapshot.executableName, command: snapshot.command)
                } else {
                    currentCommand ?? "unknown"
                }
                found.append(PortInfo(
                    port: port,
                    address: address,
                    pid: pid,
                    processName: displayName,
                    agentKind: agentByPid[pid]))
            }
        }

        let containerNames = self.containerPortNames(for: found)
        return found.map { portInfo in
            guard let name = containerNames[portInfo.port] else { return portInfo }
            return PortInfo(
                port: portInfo.port,
                address: portInfo.address,
                pid: portInfo.pid,
                processName: name,
                agentKind: portInfo.agentKind)
        }.sorted { $0.port < $1.port }
    }

    // MARK: - Private

    private static func containerPortNames(for ports: [PortInfo]) -> [Int: String] {
        let portNumbers = Set(ports.map(\.port))
        var map: [Int: String] = [:]
        for runtime in ["docker", "podman", "nerdctl"] {
            for (port, name) in self.containerPortMap(runtime: runtime) {
                if portNumbers.contains(port) { map[port] = "\(name) (\(runtime))" }
            }
        }
        return map
    }

    private static func containerPortMap(runtime: String) -> [Int: String] {
        guard let path = ShellRunner.executablePath(named: runtime) else { return [:] }
        let result = ShellRunner.run(launchPath: path, arguments: ["ps", "--format", "{{.Names}}\t{{.Ports}}"])
        guard result.status == 0 else { return [:] }

        var map: [Int: String] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let containerName = String(parts[0])
            for mapping in parts[1].split(separator: ",") {
                let s = mapping.trimmingCharacters(in: .whitespaces)
                guard let arrowIdx = s.range(of: "->") else { continue }
                let hostPart = String(s[..<arrowIdx.lowerBound])
                let portStr = hostPart.split(separator: ":").last.map(String.init) ?? hostPart
                if let hostPort = Int(portStr) { map[hostPort] = containerName }
            }
        }
        return map
    }
}
