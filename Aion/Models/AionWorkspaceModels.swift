import Foundation

// MARK: - Full Web-Parity Entities (Agents, Providers, MCP, Workspace, Confirmations, Server Settings)

struct AionManagedAgent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let backend: String
    let command: String?
    var enabled: Bool
    var installed: Bool
    var healthStatus: String?
}

struct AionProvider: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let platform: String
    let baseURL: String
    var models: [String]
    let hasAPIKey: Bool
    var enabled: Bool
}

struct AionMCPServer: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let transportType: String
    let endpointOrCommand: String
    var enabled: Bool
    var status: String
}

struct AionWorkspaceFile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int?
}

struct AionConfirmationItem: Identifiable, Hashable, Sendable {
    let id: String          // call_id
    let msgID: String?
    let title: String
    let description: String
    let options: [AionConfirmationOption]
}

struct AionConfirmationOption: Identifiable, Hashable, Sendable {
    let id: String          // confirm key / value
    let label: String
    let isDestructive: Bool
    let isAlwaysAllow: Bool
}

struct AionSlashCommand: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
}

struct AionRemoteSettings: Equatable, Sendable {
    var language: String = "en-US"
    var notificationEnabled: Bool = true
    var cronNotificationEnabled: Bool = true
    var commandQueueEnabled: Bool = true
    var saveUploadToWorkspace: Bool = true
}

struct AionSystemInfo: Equatable, Sendable {
    var version: String = ""
    var platform: String = ""
    var arch: String = ""
    var hostname: String = ""
}
