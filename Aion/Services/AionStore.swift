import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AionStore {
    // MARK: - Published App State

    var selectedTab: AionTab = .home
    var conversations: [AionConversation] = []
    var activeConversationID: UUID?
    var skills: [AionSkill] = AionFixtures.sampleSkills
    var cronTasks: [AionCronTask] = AionFixtures.sampleCronTasks

    var serverConfig: AionServerConfig = AionServerConfig() {
        didSet { persistSettings() }
    }

    var appearanceMode: AionAppearanceMode = .system {
        didSet { persistSettings() }
    }

    var selectedModelID: String = AionModelOption.defaults[0].id
    var connectionState: AionConnectionState = .demo

    var isStreaming: Bool = false
    var activeErrorBanner: String?
    var isVoiceModePresented: Bool = false
    var pendingDraftPrompt: String = ""
    var selectedSkillForNextPrompt: AionSkill?

    // MARK: - Private Services

    private let apiClient = AionAPIClient()
    private var streamingTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum StorageKeys {
        static let serverConfig = "aion.serverConfig.v1"
        static let appearance = "aion.appearanceMode.v1"
    }

    init() {
        loadPersistedState()
        if conversations.isEmpty {
            conversations = AionFixtures.sampleConversations
        }
        if serverConfig.mode == .demo {
            connectionState = .demo
        } else {
            Task { await refreshConnection() }
        }
    }

    // MARK: - Computed Helpers

    var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var activeCronCount: Int {
        cronTasks.filter(\.isActive).count
    }

    var enabledSkillsCount: Int {
        skills.filter(\.isEnabled).count
    }

    var activeModel: AionModelOption {
        AionModelOption.defaults.first(where: { $0.id == selectedModelID }) ?? AionModelOption.defaults[0]
    }

    func conversation(for id: UUID) -> AionConversation? {
        conversations.first(where: { $0.id == id })
    }

    // MARK: - Conversation Lifecycle

    @discardableResult
    func createNewConversation(
        title: String = "New Thread",
        initialPrompt: String? = nil,
        skill: AionSkill? = nil
    ) -> AionConversation {
        let icon = skill?.iconName ?? "bubble.left.fill"
        let convo = AionConversation(
            title: title,
            iconName: icon,
            modelID: selectedModelID,
            updatedAt: Date(),
            messages: []
        )
        conversations.insert(convo, at: 0)
        activeConversationID = convo.id
        selectedSkillForNextPrompt = skill
        persistConversations()

        if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendMessage(initialPrompt, in: convo.id)
        }
        return convo
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        if activeConversationID == id {
            activeConversationID = nil
        }
        persistConversations()
    }

    // MARK: - Send & Stream Messages

    func sendMessage(_ text: String, attachments: [AionAttachment] = [], in conversationID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let convoIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        stopStreaming()
        activeErrorBanner = nil
        AionHaptics.light()

        // Auto-title fresh threads from the first user prompt
        if conversations[convoIndex].messages.isEmpty {
            let cleanTitle = String(trimmed.prefix(38))
            conversations[convoIndex].title = cleanTitle.count < trimmed.count ? "\(cleanTitle)…" : cleanTitle
        }

        let historySnapshot = conversations[convoIndex].messages
        let userMessage = AionMessage(role: .user, content: trimmed, attachments: attachments)
        let assistantPlaceholder = AionMessage(role: .assistant, content: "")

        conversations[convoIndex].messages.append(userMessage)
        conversations[convoIndex].messages.append(assistantPlaceholder)
        conversations[convoIndex].updatedAt = Date()

        // Bubble updated thread to top
        let moved = conversations.remove(at: convoIndex)
        conversations.insert(moved, at: 0)

        let assistantID = assistantPlaceholder.id
        let skillToUse = selectedSkillForNextPrompt
        selectedSkillForNextPrompt = nil
        let modelToUse = moved.modelID
        let configSnapshot = serverConfig

        isStreaming = true
        persistConversations()

        streamingTask = Task {
            let stream = await apiClient.streamReply(
                prompt: trimmed,
                history: historySnapshot,
                modelID: modelToUse,
                activeSkill: skillToUse,
                config: configSnapshot
            )

            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    self.apply(event: event, conversationID: conversationID, messageID: assistantID)
                }
                self.isStreaming = false
                self.persistConversations()
                AionHaptics.success()
            } catch {
                self.isStreaming = false
                self.activeErrorBanner = error.localizedDescription
                self.appendFallbackError(error.localizedDescription, conversationID: conversationID, messageID: assistantID)
                self.persistConversations()
                AionHaptics.warning()
            }
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
    }

    private func apply(event: AionStreamEvent, conversationID: UUID, messageID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        switch event {
        case .delta(let chunk):
            conversations[cIdx].messages[mIdx].content += chunk
        case .toolStarted(let name, let detail):
            conversations[cIdx].messages[mIdx].toolCalls.append(
                AionToolCall(name: name, detail: detail, status: .running)
            )
        case .toolCompleted(let name, let detail, let duration):
            if let tIdx = conversations[cIdx].messages[mIdx].toolCalls.lastIndex(where: { $0.name == name }) {
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].detail = detail
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].status = .completed
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].durationSeconds = duration
            } else {
                conversations[cIdx].messages[mIdx].toolCalls.append(
                    AionToolCall(name: name, detail: detail, status: .completed, durationSeconds: duration)
                )
            }
        case .summaryCard(let card):
            conversations[cIdx].messages[mIdx].summaryCard = card
        case .suggestions(let pills):
            conversations[cIdx].messages[mIdx].followUpSuggestions = pills
        case .finished:
            conversations[cIdx].updatedAt = Date()
        }
    }

    private func appendFallbackError(_ message: String, conversationID: UUID, messageID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        if conversations[cIdx].messages[mIdx].content.isEmpty {
            conversations[cIdx].messages[mIdx].content = "Unable to reach the configured API server (\(message)). Verify your URL in Settings or switch to Demo Mode."
        }
    }

    // MARK: - Server Connection

    func refreshConnection() async {
        connectionState = .connecting
        let result = await apiClient.testConnection(config: serverConfig)
        connectionState = result
    }

    // MARK: - Skills & Cron Management

    func toggleSkill(_ id: String) {
        guard let idx = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[idx].isEnabled.toggle()
        AionHaptics.selection()
    }

    func toggleCronTask(_ id: UUID) {
        guard let idx = cronTasks.firstIndex(where: { $0.id == id }) else { return }
        cronTasks[idx].isActive.toggle()
        AionHaptics.selection()
        persistCronTasks()
    }

    func addCronTask(name: String, scheduleExpression: String, scheduleLabel: String, prompt: String) {
        let task = AionCronTask(
            name: name,
            scheduleExpression: scheduleExpression,
            scheduleLabel: scheduleLabel,
            prompt: prompt,
            isActive: true
        )
        cronTasks.insert(task, at: 0)
        AionHaptics.success()
        persistCronTasks()
    }

    func deleteCronTask(_ id: UUID) {
        cronTasks.removeAll(where: { $0.id == id })
        persistCronTasks()
    }

    func runCronTaskNow(_ task: AionCronTask) -> AionConversation {
        if let idx = cronTasks.firstIndex(where: { $0.id == task.id }) {
            cronTasks[idx].lastRunAt = Date()
            persistCronTasks()
        }
        return createNewConversation(title: task.name, initialPrompt: task.prompt)
    }

    // MARK: - Local JSON Persistence

    private var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Aion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persistSettings() {
        if let encoded = try? JSONEncoder().encode(serverConfig) {
            defaults.set(encoded, forKey: StorageKeys.serverConfig)
        }
        defaults.set(appearanceMode.rawValue, forKey: StorageKeys.appearance)
    }

    private func persistConversations() {
        let url = storageDirectory.appendingPathComponent("conversations.json")
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistCronTasks() {
        let url = storageDirectory.appendingPathComponent("cron_tasks.json")
        if let data = try? JSONEncoder().encode(cronTasks) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadPersistedState() {
        if let rawConfig = defaults.data(forKey: StorageKeys.serverConfig),
           let decoded = try? JSONDecoder().decode(AionServerConfig.self, from: rawConfig) {
            serverConfig = decoded
        }
        if let rawAppearance = defaults.string(forKey: StorageKeys.appearance),
           let mode = AionAppearanceMode(rawValue: rawAppearance) {
            appearanceMode = mode
        }

        let convURL = storageDirectory.appendingPathComponent("conversations.json")
        if let data = try? Data(contentsOf: convURL),
           let decoded = try? JSONDecoder().decode([AionConversation].self, from: data) {
            conversations = decoded
        }

        let cronURL = storageDirectory.appendingPathComponent("cron_tasks.json")
        if let data = try? Data(contentsOf: cronURL),
           let decoded = try? JSONDecoder().decode([AionCronTask].self, from: data) {
            cronTasks = decoded
        }
    }
}
