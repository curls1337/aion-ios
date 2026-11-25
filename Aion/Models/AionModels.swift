import Foundation

// MARK: - Navigation Tabs

enum AionTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case search
    case workspace
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .workspace: return "Skills"
        case .settings: return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "bubble.left.and.text.bubble.right.fill"
        case .search: return "magnifyingglass"
        case .workspace: return "square.grid.2x2.fill"
        case .settings: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Authenticated User & Assistants

struct AionUser: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let role: String?
}

struct AionAssistant: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let backend: String
    let avatar: String?
    let enabled: Bool
}

// MARK: - Models & Providers

struct AionModelOption: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let provider: String
    let badge: String

    static let defaults: [AionModelOption] = [
        AionModelOption(id: "aion-default", displayName: "Aion Agent", provider: "AionUi", badge: "Auto"),
        AionModelOption(id: "gemini-2.5-pro", displayName: "Gemini Pro", provider: "Google", badge: "Fast"),
        AionModelOption(id: "claude-sonnet-4", displayName: "Claude Sonnet", provider: "Anthropic", badge: "Code"),
        AionModelOption(id: "gpt-4o", displayName: "GPT-4o", provider: "OpenAI", badge: "Omni")
    ]
}

// MARK: - Conversation & Message Models

struct AionConversation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var remoteID: String?
    var title: String
    var iconName: String
    var modelID: String
    var conversationType: String?
    var assistantID: String?
    var updatedAt: Date
    var messages: [AionMessage]
    var hasLoadedMessages: Bool

    init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        title: String,
        iconName: String = "bubble.left.fill",
        modelID: String = "aion-default",
        conversationType: String? = nil,
        assistantID: String? = nil,
        updatedAt: Date = Date(),
        messages: [AionMessage] = [],
        hasLoadedMessages: Bool = true
    ) {
        self.id = id
        self.remoteID = remoteID
        self.title = title
        self.iconName = iconName
        self.modelID = modelID
        self.conversationType = conversationType
        self.assistantID = assistantID
        self.updatedAt = updatedAt
        self.messages = messages
        self.hasLoadedMessages = hasLoadedMessages
    }

    var previewText: String {
        if let last = messages.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return last.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let conversationType, !conversationType.isEmpty {
            return "\(conversationType.uppercased()) · Tap to open"
        }
        return "Tap to open conversation"
    }
}

struct AionMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    var remoteMsgID: String?
    let role: Role
    var content: String
    var thinking: String?
    var thinkingSubject: String?
    let createdAt: Date
    var toolCalls: [AionToolCall]
    var planEntries: [AionPlanEntry]
    var summaryCard: AionSummaryCard?
    var attachments: [AionAttachment]
    var followUpSuggestions: [String]

    init(
        id: UUID = UUID(),
        remoteMsgID: String? = nil,
        role: Role,
        content: String,
        thinking: String? = nil,
        thinkingSubject: String? = nil,
        createdAt: Date = Date(),
        toolCalls: [AionToolCall] = [],
        planEntries: [AionPlanEntry] = [],
        summaryCard: AionSummaryCard? = nil,
        attachments: [AionAttachment] = [],
        followUpSuggestions: [String] = []
    ) {
        self.id = id
        self.remoteMsgID = remoteMsgID
        self.role = role
        self.content = content
        self.thinking = thinking
        self.thinkingSubject = thinkingSubject
        self.createdAt = createdAt
        self.toolCalls = toolCalls
        self.planEntries = planEntries
        self.summaryCard = summaryCard
        self.attachments = attachments
        self.followUpSuggestions = followUpSuggestions
    }
}

struct AionPlanEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var status: String // pending, in_progress, completed
}

struct AionLiveActivity: Equatable, Sendable {
    enum Phase: String, Sendable {
        case starting
        case thinking
        case runningTool
        case writing
        case waitingApproval
    }

    var phase: Phase
    var title: String
    var detail: String
    var startedAt: Date
}

enum AionPermissionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case defaultMode = "default"
    case autoApprove = "auto_edit"
    case fullAuto = "yolo"
    case planOnly = "plan"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultMode: return "Default"
        case .autoApprove: return "Auto Edit"
        case .fullAuto: return "Full Auto"
        case .planOnly: return "Plan Only"
        }
    }

    var iconName: String {
        switch self {
        case .defaultMode: return "shield"
        case .autoApprove: return "shield.lefthalf.filled"
        case .fullAuto: return "bolt.shield.fill"
        case .planOnly: return "list.clipboard"
        }
    }
}

enum AionThoughtLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = ""
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue.isEmpty ? "auto" : rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

struct AionToolCall: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    let id: UUID
    var callID: String?
    let name: String
    var detail: String
    var status: Status
    var durationSeconds: Double?

    init(
        id: UUID = UUID(),
        callID: String? = nil,
        name: String,
        detail: String,
        status: Status = .completed,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.callID = callID
        self.name = name
        self.detail = detail
        self.status = status
        self.durationSeconds = durationSeconds
    }
}

struct AionSummaryCard: Codable, Hashable, Sendable {
    let title: String
    let bullets: [String]
    let attachmentName: String?
}

struct AionAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let sizeLabel: String
    var remotePath: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String = "application/octet-stream",
        sizeLabel: String = "124 KB",
        remotePath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeLabel = sizeLabel
        self.remotePath = remotePath
    }
}

// MARK: - Skills & Scheduled Cron Tasks

struct AionSkill: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let iconName: String
    let category: String
    let samplePrompt: String
    var isEnabled: Bool
}

struct AionCronTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var remoteJobID: String?
    var name: String
    var scheduleExpression: String
    var scheduleLabel: String
    var prompt: String
    var isActive: Bool
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        remoteJobID: String? = nil,
        name: String,
        scheduleExpression: String,
        scheduleLabel: String,
        prompt: String,
        isActive: Bool = true,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.remoteJobID = remoteJobID
        self.name = name
        self.scheduleExpression = scheduleExpression
        self.scheduleLabel = scheduleLabel
        self.prompt = prompt
        self.isActive = isActive
        self.lastRunAt = lastRunAt
    }
}

// MARK: - Search Hit

struct AionSearchHit: Identifiable, Hashable, Sendable {
    let id: String
    let conversationRemoteID: String
    let conversationTitle: String
    let previewText: String
    let createdAt: Date
}

// MARK: - Backend Connection Configuration

enum AionBackendMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case aionWebUI = "AionUi Remote"
    case openAICompatible = "OpenAI API"
    case demo = "Demo"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .aionWebUI:
            return "Live AionUi REST + WebSocket (e.g. https://aion.5nod.com)"
        case .openAICompatible:
            return "Standard /v1/chat/completions SSE streaming"
        case .demo:
            return "Offline preview simulator (no server needed)"
        }
    }
}

struct AionServerConfig: Codable, Equatable, Sendable {
    var mode: AionBackendMode = .aionWebUI
    var baseURL: String = "https://aion.5nod.com"
    var username: String = "admin"
    var password: String = ""
    var apiKey: String = ""
    var customModelName: String = "gpt-4o"

    var normalizedBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        let cleaned = withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
        return URL(string: cleaned)
    }

    var webSocketURL: URL? {
        guard let httpURL = normalizedBaseURL,
              var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = "/ws"
        return components.url
    }
}

enum AionConnectionState: Equatable, Sendable {
    case demo
    case needsLogin
    case connecting
    case connected(latencyMs: Int, username: String?)
    case offline(reason: String)

    var badgeLabel: String {
        switch self {
        case .demo:
            return "Demo Mode"
        case .needsLogin:
            return "Sign In Required"
        case .connecting:
            return "Connecting..."
        case .connected(let latencyMs, let username):
            if let username, !username.isEmpty {
                return "\(username) · \(latencyMs)ms"
            }
            return "Aion API Online · \(latencyMs)ms"
        case .offline:
            return "API Offline"
        }
    }

    var isHealthy: Bool {
        switch self {
        case .demo, .connected:
            return true
        case .needsLogin, .connecting, .offline:
            return false
        }
    }
}

// MARK: - Demo Fixtures (Used only when Demo Mode is explicitly selected)

enum AionFixtures {
    static let sampleSkills: [AionSkill] = [
        AionSkill(
            id: "aionui-config",
            name: "Aion Config",
            summary: "Manage assistants, model providers, MCP servers, and workspace settings.",
            iconName: "slider.horizontal.3",
            category: "System",
            samplePrompt: "List my active assistants and enabled MCP servers.",
            isEnabled: true
        ),
        AionSkill(
            id: "officecli",
            name: "Office Documents",
            summary: "Generate, analyze, and format Word, Excel, and PowerPoint decks.",
            iconName: "doc.richtext.fill",
            category: "Productivity",
            samplePrompt: "Summarize the Q3 report and draft an executive brief.",
            isEnabled: true
        ),
        AionSkill(
            id: "cron",
            name: "Scheduled Cron",
            summary: "Create recurring background tasks and automated daily digests.",
            iconName: "clock.badge.checkmark.fill",
            category: "Automation",
            samplePrompt: "Create a weekday 8:00 AM briefing of my pending tasks.",
            isEnabled: true
        )
    ]

    static let sampleCronTasks: [AionCronTask] = [
        AionCronTask(
            name: "Morning Executive Digest",
            scheduleExpression: "0 8 * * MON-FRI",
            scheduleLabel: "Weekdays · 08:00",
            prompt: "Compile overnight GitHub PRs, API health metrics, and top 3 priorities.",
            isActive: true,
            lastRunAt: Date().addingTimeInterval(-3600 * 5)
        )
    ]

    static let sampleConversations: [AionConversation] = [
        AionConversation(
            title: "Q3 Product Roadmap",
            iconName: "chart.bar.doc.horizontal.fill",
            modelID: "aion-default",
            updatedAt: Date().addingTimeInterval(-60 * 18),
            messages: [
                AionMessage(
                    role: .user,
                    content: "Summarize the Q3 report",
                    createdAt: Date().addingTimeInterval(-60 * 20)
                ),
                AionMessage(
                    role: .assistant,
                    content: "Here is the key overview from your Q3 performance report, including revenue growth and regional API metrics.",
                    createdAt: Date().addingTimeInterval(-60 * 18),
                    toolCalls: [
                        AionToolCall(
                            name: "officecli",
                            detail: "Parsed report.docx (14 pages)",
                            status: .completed,
                            durationSeconds: 0.4
                        )
                    ],
                    summaryCard: AionSummaryCard(
                        title: "Executive Summary",
                        bullets: [
                            "Revenue grew 18% quarter over quarter",
                            "API uptime reached 99.98% globally"
                        ],
                        attachmentName: "report.docx"
                    ),
                    followUpSuggestions: ["Draft email", "Key risks", "Share"]
                )
            ]
        )
    ]
}
