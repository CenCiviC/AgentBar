import Foundation

struct AgentProcess: Identifiable, Hashable {
    let id: Int32
    let kind: AgentKind
    let ownerKind: AgentKind?
    let ownerPid: Int32?
    let name: String
    let tty: String?
    let terminalLocation: String?
    let command: String
    let cpu: Double
    let memMB: Double
    let isZombie: Bool
}

struct PortInfo: Identifiable {
    var id: String {
        "\(self.pid):\(self.port)"
    }

    let port: Int
    let address: String
    let pid: Int32
    let processName: String
    let agentKind: AgentKind?
}

/// Known macOS system daemons that appear in lsof TCP LISTEN output.
let macOSSystemProcessNames: Set<String> = [
    "rapportd", "remoted", "screensharingd", "sharingd",
    "mDNSResponder", "netbiosd", "smbd", "nmbd", "sshd",
    "configd", "launchd", "UserEventAgent", "AirPlayXPCHelper",
    "mediaremoted", "apsd", "imagent", "CommCenter", "avconferenced",
    "coreduetd", "symptomsd", "nesessionmanager", "networkd_privilege",
    "cloudd", "bird", "nsurlsessiond", "IMDPersistenceAgent",
    "IMTransferAgent", "lsd", "secd", "trustd", "distnoted",
    "ControlCenter", "assistantd", "callservicesd", "contactsd",
    "ctkd", "cupsd", "photoanalysisd", "routined", "remindd",
    "locationd", "tccd", "sandboxd", "timed", "watchdogd",
    "akd", "findmylocated", "parsecd", "bookdatastored",
    "CalendarAgent", "AddressBookSourceSync", "CoreLocationAgent",
]
