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
    var updatedAt: Date
    var messages: [AionMessage]

    init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        title: String,
        iconName: String = "doc.text.fill",
        modelID: String = "aion-default",
        updatedAt: Date = Date(),
        messages: [AionMessage] = []
    ) {
        self.id = id
        self.remoteID = remoteID
        self.title = title
        self.iconName = iconName
        self.modelID = modelID
        self.updatedAt = updatedAt
        self.messages = messages
    }

    var previewText: String {
        messages.last?.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Start a new conversation"
    }
}

struct AionMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    var toolCalls: [AionToolCall]
    var summaryCard: AionSummaryCard?
    var attachments: [AionAttachment]
    var followUpSuggestions: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        toolCalls: [AionToolCall] = [],
        summaryCard: AionSummaryCard? = nil,
        attachments: [AionAttachment] = [],
        followUpSuggestions: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolCalls = toolCalls
        self.summaryCard = summaryCard
        self.attachments = attachments
        self.followUpSuggestions = followUpSuggestions
    }
}

struct AionToolCall: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    let id: UUID
    let name: String
    var detail: String
    var status: Status
    var durationSeconds: Double?

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        status: Status = .completed,
        durationSeconds: Double? = nil
    ) {
        self.id = id
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

    init(id: UUID = UUID(), fileName: String, mimeType: String = "application/octet-stream", sizeLabel: String = "124 KB") {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeLabel = sizeLabel
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
    var name: String
    var scheduleExpression: String
    var scheduleLabel: String
    var prompt: String
    var isActive: Bool
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        scheduleExpression: String,
        scheduleLabel: String,
        prompt: String,
        isActive: Bool = true,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.scheduleExpression = scheduleExpression
        self.scheduleLabel = scheduleLabel
        self.prompt = prompt
        self.isActive = isActive
        self.lastRunAt = lastRunAt
    }
}

// MARK: - Backend Connection Configuration

enum AionBackendMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case demo = "Demo Mode"
    case aionWebUI = "AionUi WebUI API"
    case openAICompatible = "OpenAI-Compatible API"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .demo:
            return "Instant offline preview with realistic streaming"
        case .aionWebUI:
            return "Direct HTTP + WebSocket bridge to AionUi (:25808)"
        case .openAICompatible:
            return "Standard /v1/chat/completions SSE streaming"
        }
    }
}

struct AionServerConfig: Codable, Equatable, Sendable {
    var mode: AionBackendMode = .demo
    var baseURL: String = "http://127.0.0.1:25808"
    var username: String = "admin"
    var password: String = ""
    var apiKey: String = ""
    var customModelName: String = "gpt-4o"

    var normalizedBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "http://\(trimmed)"
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
    case connecting
    case connected(latencyMs: Int)
    case offline(reason: String)

    var badgeLabel: String {
        switch self {
        case .demo:
            return "Aion Demo Ready"
        case .connecting:
            return "Connecting..."
        case .connected(let latencyMs):
            return "Aion API Online · \(latencyMs)ms"
        case .offline:
            return "API Offline"
        }
    }

    var isHealthy: Bool {
        switch self {
        case .demo, .connected:
            return true
        case .connecting, .offline:
            return false
        }
    }
}

// MARK: - Seed / Demo Fixtures

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
        ),
        AionSkill(
            id: "conversation-create",
            name: "Thread Spawner",
            summary: "Spin up parallel isolated agent conversations for multi-track work.",
            iconName: "bubble.left.and.exclamationmark.bubble.right.fill",
            category: "Agents",
            samplePrompt: "Start a dedicated workspace conversation for iOS release QA.",
            isEnabled: true
        ),
        AionSkill(
            id: "session-message",
            name: "Cross-Session Sync",
            summary: "Send context and handoffs between running Aion conversations.",
            iconName: "arrow.triangle.2.circlepath.circle.fill",
            category: "Agents",
            samplePrompt: "Notify my backend agent that the mobile API schema is ready.",
            isEnabled: true
        ),
        AionSkill(
            id: "skill-creator",
            name: "Skill Builder",
            summary: "Author and validate new reusable Aion skills and workflows.",
            iconName: "wand.and.stars",
            category: "Developer",
            samplePrompt: "Help me scaffold a custom skill for deployment checklists.",
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
        ),
        AionCronTask(
            name: "API Latency Watchdog",
            scheduleExpression: "*/15 * * * *",
            scheduleLabel: "Every 15 minutes",
            prompt: "Verify Aion WebUI endpoint latency and alert if p95 exceeds 400ms.",
            isActive: true,
            lastRunAt: Date().addingTimeInterval(-60 * 12)
        ),
        AionCronTask(
            name: "Weekly Product Recap",
            scheduleExpression: "0 17 * * FRI",
            scheduleLabel: "Fridays · 17:00",
            prompt: "Summarize shipped iOS features and prepare changelog notes.",
            isActive: true,
            lastRunAt: Date().addingTimeInterval(-86400 * 3)
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
                            "API uptime reached 99.98% globally",
                            "Mobile client latency dropped by 42%"
                        ],
                        attachmentName: "report.docx"
                    ),
                    followUpSuggestions: ["Draft email", "Key risks", "Share"]
                )
            ]
        ),
        AionConversation(
            title: "API Latency Review",
            iconName: "bolt.horizontal.circle.fill",
            modelID: "claude-sonnet-4",
            updatedAt: Date().addingTimeInterval(-3600 * 3),
            messages: [
                AionMessage(
                    role: .user,
                    content: "How should the iOS app connect to AionUi over Tailscale?",
                    createdAt: Date().addingTimeInterval(-3600 * 3 - 60)
                ),
                AionMessage(
                    role: .assistant,
                    content: "Start AionUi with WebUI remote mode enabled, then point the iOS client to your Tailscale MagicDNS or `100.x.x.x:25808` address.\n\n```bash\nAionUi --webui --remote\n```\n\nThe iOS app automatically negotiates JWT login and opens a persistent WebSocket stream with low-overhead heartbeats.",
                    createdAt: Date().addingTimeInterval(-3600 * 3),
                    followUpSuggestions: ["Test connection", "Security tips"]
                )
            ]
        ),
        AionConversation(
            title: "Weekly Digest",
            iconName: "calendar.badge.clock",
            modelID: "gemini-2.5-pro",
            updatedAt: Date().addingTimeInterval(-86400),
            messages: [
                AionMessage(
                    role: .user,
                    content: "Give me a quick recap of my active automations.",
                    createdAt: Date().addingTimeInterval(-86400 - 45)
                ),
                AionMessage(
                    role: .assistant,
                    content: "All 3 scheduled cron workflows ran cleanly this week with zero retries. Your next scheduled briefing triggers tomorrow at 08:00.",
                    createdAt: Date().addingTimeInterval(-86400),
                    followUpSuggestions: ["Pause watchdog", "Add schedule"]
                )
            ]
        )
    ]
}
