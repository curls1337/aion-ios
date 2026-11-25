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
    var assistants: [AionAssistant] = []
    var selectedAssistantID: String?
    var skills: [AionSkill] = []
    var cronTasks: [AionCronTask] = []
    var remoteSearchHits: [AionSearchHit] = []

    var currentUser: AionUser?
    var isWebSocketConnected: Bool = false
    var isSyncingWorkspace: Bool = false
    var isLoadingMessages: Bool = false
    var isLoginSheetPresented: Bool = false
    var loginErrorMessage: String?
    var isSigningIn: Bool = false

    var serverConfig: AionServerConfig = AionServerConfig() {
        didSet { persistSettings() }
    }

    var appearanceMode: AionAppearanceMode = .system {
        didSet { persistSettings() }
    }

    var selectedModelID: String = AionModelOption.defaults[0].id
    var connectionState: AionConnectionState = .connecting

    var isStreaming: Bool = false
    var streamingConversationRemoteID: String?
    var activeErrorBanner: String?
    var isVoiceModePresented: Bool = false
    var selectedSkillForNextPrompt: AionSkill?

    // MARK: - Private Services

    private let apiClient = AionAPIClient()
    private var streamingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum StorageKeys {
        static let serverConfig = "aion.serverConfig.v2"
        static let appearance = "aion.appearanceMode.v1"
        static let keychainPassword = "aion.webui.password"
        static let keychainAPIKey = "aion.api.key"
    }

    init() {
        loadPersistedState()
        if serverConfig.mode == .demo {
            connectionState = .demo
            if conversations.isEmpty { conversations = AionFixtures.sampleConversations }
            if skills.isEmpty { skills = AionFixtures.sampleSkills }
            if cronTasks.isEmpty { cronTasks = AionFixtures.sampleCronTasks }
        } else {
            Task { await bootstrapLiveSession() }
        }
    }

    // MARK: - Computed Helpers

    var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        case 17..<22: base = "Good evening"
        default: base = "Good night"
        }
        return base
    }

    var activeCronCount: Int {
        cronTasks.filter(\.isActive).count
    }

    var enabledSkillsCount: Int {
        skills.filter(\.isEnabled).count
    }

    var selectedAssistant: AionAssistant? {
        if let id = selectedAssistantID, let found = assistants.first(where: { $0.id == id }) {
            return found
        }
        return assistants.first(where: \.enabled) ?? assistants.first
    }

    var activeModel: AionModelOption {
        AionModelOption.defaults.first(where: { $0.id == selectedModelID }) ?? AionModelOption.defaults[0]
    }

    var headerAssistantLabel: String {
        if serverConfig.mode == .aionWebUI, let assistant = selectedAssistant {
            return assistant.name
        }
        return activeModel.displayName
    }

    func conversation(for id: UUID) -> AionConversation? {
        conversations.first(where: { $0.id == id })
    }

    func conversation(forRemoteID remoteID: String) -> AionConversation? {
        conversations.first(where: { $0.remoteID == remoteID })
    }

    // MARK: - Live Session Bootstrap & Auth

    func bootstrapLiveSession() async {
        guard serverConfig.mode != .demo else {
            connectionState = .demo
            return
        }

        connectionState = .connecting
        let result = await apiClient.checkSession(config: serverConfig)
        connectionState = result.state
        currentUser = result.user

        switch result.state {
        case .connected:
            isLoginSheetPresented = false
            if serverConfig.mode == .aionWebUI {
                await startRealtimeStream()
                await syncWorkspace()
            }
        case .needsLogin:
            isLoginSheetPresented = true
        case .offline, .demo, .connecting:
            break
        }
    }

    func signIn(serverURL: String, username: String, password: String) async {
        loginErrorMessage = nil
        isSigningIn = true

        serverConfig.mode = .aionWebUI
        serverConfig.baseURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        serverConfig.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        serverConfig.password = password
        persistSettings()

        do {
            let start = Date()
            let user = try await apiClient.login(config: serverConfig)
            let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
            currentUser = user
            connectionState = .connected(latencyMs: latency, username: user.username)
            isLoginSheetPresented = false
            isSigningIn = false
            AionHaptics.success()

            await startRealtimeStream()
            await syncWorkspace()
        } catch {
            isSigningIn = false
            loginErrorMessage = error.localizedDescription
            connectionState = .needsLogin
            AionHaptics.warning()
        }
    }

    func signOut() async {
        await apiClient.logout(config: serverConfig)
        serverConfig.password = ""
        AionKeychain.delete(account: StorageKeys.keychainPassword)
        currentUser = nil
        isWebSocketConnected = false
        conversations = []
        assistants = []
        skills = []
        cronTasks = []
        connectionState = .needsLogin
        isLoginSheetPresented = true
        AionHaptics.medium()
    }

    func switchToDemoMode() {
        Task { await apiClient.disconnectWebSocket() }
        serverConfig.mode = .demo
        connectionState = .demo
        isLoginSheetPresented = false
        isWebSocketConnected = false
        if conversations.isEmpty { conversations = AionFixtures.sampleConversations }
        if skills.isEmpty { skills = AionFixtures.sampleSkills }
        if cronTasks.isEmpty { cronTasks = AionFixtures.sampleCronTasks }
        AionHaptics.selection()
    }

    func refreshConnection() async {
        await bootstrapLiveSession()
    }

    // MARK: - Live Workspace Sync (Conversations, Assistants, Skills, Cron)

    func syncWorkspace() async {
        guard serverConfig.mode == .aionWebUI else { return }
        isSyncingWorkspace = true
        let config = serverConfig

        async let convTask = try? apiClient.fetchConversations(config: config, limit: 50)
        async let asstTask = try? apiClient.fetchAssistants(config: config)
        async let skillTask = try? apiClient.fetchSkills(config: config)
        async let cronTask = try? apiClient.fetchCronJobs(config: config)

        let (fetchedConvos, fetchedAssistants, fetchedSkills, fetchedCrons) = await (convTask, asstTask, skillTask, cronTask)

        if let fetchedConvos {
            // Preserve already-loaded message arrays & local UUIDs for matching remoteIDs
            let existingByRemote = Dictionary(uniqueKeysWithValues: conversations.compactMap { c in
                c.remoteID.map { ($0, c) }
            })
            conversations = fetchedConvos.map { remote in
                if let rid = remote.remoteID, let existing = existingByRemote[rid] {
                    var updated = existing
                    updated.title = remote.title
                    updated.updatedAt = remote.updatedAt
                    updated.conversationType = remote.conversationType
                    updated.assistantID = remote.assistantID
                    return updated
                }
                return remote
            }
            persistConversations()
        }

        if let fetchedAssistants {
            assistants = fetchedAssistants
            if selectedAssistantID == nil {
                selectedAssistantID = fetchedAssistants.first(where: \.enabled)?.id ?? fetchedAssistants.first?.id
            }
        }

        if let fetchedSkills, !fetchedSkills.isEmpty {
            skills = fetchedSkills
        }

        if let fetchedCrons {
            cronTasks = fetchedCrons
            persistCronTasks()
        }

        isSyncingWorkspace = false
    }

    func loadMessagesIfNeeded(for conversationID: UUID, force: Bool = false) async {
        guard serverConfig.mode == .aionWebUI,
              let idx = conversations.firstIndex(where: { $0.id == conversationID }),
              let remoteID = conversations[idx].remoteID else {
            return
        }
        if conversations[idx].hasLoadedMessages && !force { return }

        isLoadingMessages = true
        do {
            let messages = try await apiClient.fetchMessages(conversationRemoteID: remoteID, config: serverConfig)
            if let freshIdx = conversations.firstIndex(where: { $0.id == conversationID }) {
                conversations[freshIdx].messages = messages
                conversations[freshIdx].hasLoadedMessages = true
                persistConversations()
            }
        } catch {
            activeErrorBanner = error.localizedDescription
        }
        isLoadingMessages = false
    }

    // MARK: - Persistent Real-Time WebSocket Stream

    private func startRealtimeStream() async {
        let config = serverConfig
        await apiClient.connectWebSocket(config: config) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRealtimeEvent(event)
            }
        }
    }

    private func handleRealtimeEvent(_ event: AionRealtimeEvent) {
        switch event {
        case .wsConnected:
            isWebSocketConnected = true

        case .wsDisconnected:
            isWebSocketConnected = false

        case .textDelta(let remoteConvoID, let msgID, let text, let replace, let isUser):
            guard !isUser else { return }
            guard let cIdx = ensureConversationIndex(forRemoteID: remoteConvoID) else { return }
            isStreaming = true
            streamingConversationRemoteID = remoteConvoID
            conversations[cIdx].updatedAt = Date()

            if let msgID,
               let mIdx = conversations[cIdx].messages.lastIndex(where: { $0.remoteMsgID == msgID && $0.role == .assistant }) {
                if replace {
                    conversations[cIdx].messages[mIdx].content = text
                } else {
                    conversations[cIdx].messages[mIdx].content += text
                }
            } else if let last = conversations[cIdx].messages.last, last.role == .assistant, last.remoteMsgID == nil {
                let mIdx = conversations[cIdx].messages.count - 1
                conversations[cIdx].messages[mIdx].remoteMsgID = msgID
                if replace {
                    conversations[cIdx].messages[mIdx].content = text
                } else {
                    conversations[cIdx].messages[mIdx].content += text
                }
            } else {
                conversations[cIdx].messages.append(
                    AionMessage(remoteMsgID: msgID, role: .assistant, content: text)
                )
            }

        case .thinkingDelta(let remoteConvoID, let msgID, let text):
            guard let cIdx = ensureConversationIndex(forRemoteID: remoteConvoID) else { return }
            if let last = conversations[cIdx].messages.last, last.role == .assistant {
                let mIdx = conversations[cIdx].messages.count - 1
                conversations[cIdx].messages[mIdx].thinking = (conversations[cIdx].messages[mIdx].thinking ?? "") + text
            } else {
                conversations[cIdx].messages.append(
                    AionMessage(remoteMsgID: msgID, role: .assistant, content: "", thinking: text)
                )
            }

        case .toolCall(let remoteConvoID, let msgID, let callID, let name, let detail, let status):
            guard let cIdx = ensureConversationIndex(forRemoteID: remoteConvoID) else { return }
            if conversations[cIdx].messages.last?.role != .assistant {
                conversations[cIdx].messages.append(AionMessage(remoteMsgID: msgID, role: .assistant, content: ""))
            }
            let mIdx = conversations[cIdx].messages.count - 1
            if let callID,
               let tIdx = conversations[cIdx].messages[mIdx].toolCalls.firstIndex(where: { $0.callID == callID }) {
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].detail = detail
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].status = status
            } else {
                conversations[cIdx].messages[mIdx].toolCalls.append(
                    AionToolCall(callID: callID, name: name, detail: detail, status: status)
                )
            }

        case .turnCompleted(let remoteConvoID):
            if streamingConversationRemoteID == remoteConvoID || streamingConversationRemoteID == nil {
                isStreaming = false
                streamingConversationRemoteID = nil
                AionHaptics.success()
            }
            if let convo = conversation(forRemoteID: remoteConvoID) {
                Task { await loadMessagesIfNeeded(for: convo.id, force: true) }
            }

        case .streamError(let remoteConvoID, let message):
            isStreaming = false
            activeErrorBanner = message
            if let cIdx = ensureConversationIndex(forRemoteID: remoteConvoID) {
                if conversations[cIdx].messages.last?.role == .assistant && conversations[cIdx].messages.last?.content.isEmpty == true {
                    conversations[cIdx].messages[conversations[cIdx].messages.count - 1].content = "Error: \(message)"
                }
            }
            AionHaptics.warning()

        case .summaryCard, .suggestions, .finished:
            break
        }
    }

    private func ensureConversationIndex(forRemoteID remoteID: String) -> Int? {
        conversations.firstIndex(where: { $0.remoteID == remoteID })
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
            assistantID: selectedAssistant?.id,
            updatedAt: Date(),
            messages: [],
            hasLoadedMessages: true
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
        let remoteID = conversations.first(where: { $0.id == id })?.remoteID
        conversations.removeAll(where: { $0.id == id })
        if activeConversationID == id {
            activeConversationID = nil
        }
        persistConversations()

        if serverConfig.mode == .aionWebUI, let remoteID {
            let config = serverConfig
            Task { try? await apiClient.deleteConversation(remoteID: remoteID, config: config) }
        }
    }

    // MARK: - Send & Stream Messages

    func sendMessage(_ text: String, attachments: [AionAttachment] = [], in conversationID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let convoIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        activeErrorBanner = nil
        AionHaptics.light()

        if conversations[convoIndex].messages.isEmpty {
            let cleanTitle = String(trimmed.prefix(40))
            conversations[convoIndex].title = cleanTitle.count < trimmed.count ? "\(cleanTitle)…" : cleanTitle
        }

        let historySnapshot = conversations[convoIndex].messages
        let userMessage = AionMessage(role: .user, content: trimmed, attachments: attachments)
        let assistantPlaceholder = AionMessage(role: .assistant, content: "")

        conversations[convoIndex].messages.append(userMessage)
        conversations[convoIndex].messages.append(assistantPlaceholder)
        conversations[convoIndex].updatedAt = Date()

        let moved = conversations.remove(at: convoIndex)
        conversations.insert(moved, at: 0)

        let assistantID = assistantPlaceholder.id
        let skillToUse = selectedSkillForNextPrompt
        selectedSkillForNextPrompt = nil
        let configSnapshot = serverConfig

        isStreaming = true
        persistConversations()

        if configSnapshot.mode == .aionWebUI {
            streamingTask?.cancel()
            streamingTask = Task {
                do {
                    // Create remote conversation on AionUi server if this is a brand-new thread
                    var remoteID = self.conversation(for: conversationID)?.remoteID
                    if remoteID == nil {
                        let created = try await apiClient.createConversation(
                            name: moved.title,
                            assistantID: moved.assistantID ?? self.selectedAssistant?.id,
                            config: configSnapshot
                        )
                        remoteID = created.remoteID
                        if let idx = self.conversations.firstIndex(where: { $0.id == conversationID }) {
                            self.conversations[idx].remoteID = created.remoteID
                            self.conversations[idx].conversationType = created.conversationType
                        }
                    }

                    guard let targetRemoteID = remoteID else {
                        throw AionAPIError.decodingFailed
                    }
                    self.streamingConversationRemoteID = targetRemoteID

                    if !self.isWebSocketConnected {
                        await self.startRealtimeStream()
                    }

                    let skillList = skillToUse.map { [$0.id] } ?? []
                    let fileList = attachments.compactMap(\.remotePath)

                    try await apiClient.sendConversationMessage(
                        remoteID: targetRemoteID,
                        content: trimmed,
                        files: fileList,
                        injectSkills: skillList,
                        config: configSnapshot
                    )
                } catch is CancellationError {
                    self.isStreaming = false
                } catch AionAPIError.unauthorized {
                    self.isStreaming = false
                    self.connectionState = .needsLogin
                    self.isLoginSheetPresented = true
                } catch {
                    self.isStreaming = false
                    self.activeErrorBanner = error.localizedDescription
                    self.appendErrorToAssistant(error.localizedDescription, conversationID: conversationID, messageID: assistantID)
                    AionHaptics.warning()
                }
            }
            return
        }

        // OpenAI-Compatible or Demo Mode fallback streaming
        streamingTask?.cancel()
        streamingTask = Task {
            let stream = await apiClient.streamFallbackReply(
                prompt: trimmed,
                history: historySnapshot,
                modelID: moved.modelID,
                activeSkill: skillToUse,
                config: configSnapshot
            )

            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    self.applyLocalStream(event: event, conversationID: conversationID, messageID: assistantID)
                }
                self.isStreaming = false
                self.persistConversations()
                AionHaptics.success()
            } catch {
                self.isStreaming = false
                self.activeErrorBanner = error.localizedDescription
                self.appendErrorToAssistant(error.localizedDescription, conversationID: conversationID, messageID: assistantID)
                AionHaptics.warning()
            }
        }
    }

    func stopStreaming(in conversationID: UUID? = nil) {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false

        let targetRemoteID = conversationID.flatMap { conversation(for: $0)?.remoteID } ?? streamingConversationRemoteID
        streamingConversationRemoteID = nil

        if serverConfig.mode == .aionWebUI, let targetRemoteID {
            let config = serverConfig
            Task { await apiClient.cancelConversation(remoteID: targetRemoteID, config: config) }
        }
    }

    private func applyLocalStream(event: AionRealtimeEvent, conversationID: UUID, messageID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        switch event {
        case .textDelta(_, _, let chunk, let replace, _):
            if replace {
                conversations[cIdx].messages[mIdx].content = chunk
            } else {
                conversations[cIdx].messages[mIdx].content += chunk
            }
        case .toolCall(_, _, let callID, let name, let detail, let status):
            if let callID, let tIdx = conversations[cIdx].messages[mIdx].toolCalls.firstIndex(where: { $0.callID == callID }) {
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].detail = detail
                conversations[cIdx].messages[mIdx].toolCalls[tIdx].status = status
            } else {
                conversations[cIdx].messages[mIdx].toolCalls.append(
                    AionToolCall(callID: callID, name: name, detail: detail, status: status)
                )
            }
        case .summaryCard(let card):
            conversations[cIdx].messages[mIdx].summaryCard = card
        case .suggestions(let pills):
            conversations[cIdx].messages[mIdx].followUpSuggestions = pills
        default:
            break
        }
    }

    private func appendErrorToAssistant(_ message: String, conversationID: UUID, messageID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        if conversations[cIdx].messages[mIdx].content.isEmpty {
            conversations[cIdx].messages[mIdx].content = "Request failed: \(message)"
        }
    }

    // MARK: - Server-Side Search

    func performRemoteSearch(keyword: String) {
        searchTask?.cancel()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard serverConfig.mode == .aionWebUI, trimmed.count >= 2 else {
            remoteSearchHits = []
            return
        }
        let config = serverConfig
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            if let hits = try? await apiClient.searchMessages(keyword: trimmed, config: config) {
                self.remoteSearchHits = hits
            }
        }
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
        let newState = cronTasks[idx].isActive
        let remoteJobID = cronTasks[idx].remoteJobID
        AionHaptics.selection()
        persistCronTasks()

        if serverConfig.mode == .aionWebUI, let remoteJobID {
            let config = serverConfig
            Task { try? await apiClient.toggleCronJob(remoteJobID: remoteJobID, enabled: newState, config: config) }
        }
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

        if serverConfig.mode == .aionWebUI {
            let config = serverConfig
            let convoRemoteID = conversations.first?.remoteID
            Task {
                try? await apiClient.createCronJob(
                    name: name,
                    cronExpr: scheduleExpression,
                    prompt: prompt,
                    conversationRemoteID: convoRemoteID,
                    config: config
                )
                await self.syncWorkspace()
            }
        }
    }

    func deleteCronTask(_ id: UUID) {
        let remoteJobID = cronTasks.first(where: { $0.id == id })?.remoteJobID
        cronTasks.removeAll(where: { $0.id == id })
        persistCronTasks()

        if serverConfig.mode == .aionWebUI, let remoteJobID {
            let config = serverConfig
            Task { try? await apiClient.deleteCronJob(remoteJobID: remoteJobID, config: config) }
        }
    }

    func runCronTaskNow(_ task: AionCronTask) -> AionConversation? {
        if let idx = cronTasks.firstIndex(where: { $0.id == task.id }) {
            cronTasks[idx].lastRunAt = Date()
            persistCronTasks()
        }
        if serverConfig.mode == .aionWebUI, let remoteJobID = task.remoteJobID {
            let config = serverConfig
            Task {
                try? await apiClient.runCronJobNow(remoteJobID: remoteJobID, config: config)
                await self.syncWorkspace()
            }
            AionHaptics.success()
            return nil
        }
        return createNewConversation(title: task.name, initialPrompt: task.prompt)
    }

    // MARK: - Persistence (UserDefaults + Keychain + Application Support)

    private var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Aion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persistSettings() {
        // Store secrets securely in Keychain, never plaintext in UserDefaults
        var sanitized = serverConfig
        if !serverConfig.password.isEmpty {
            AionKeychain.save(serverConfig.password, account: StorageKeys.keychainPassword)
        }
        if !serverConfig.apiKey.isEmpty {
            AionKeychain.save(serverConfig.apiKey, account: StorageKeys.keychainAPIKey)
        }
        sanitized.password = ""
        sanitized.apiKey = ""

        if let encoded = try? JSONEncoder().encode(sanitized) {
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
           var decoded = try? JSONDecoder().decode(AionServerConfig.self, from: rawConfig) {
            decoded.password = AionKeychain.read(account: StorageKeys.keychainPassword) ?? ""
            decoded.apiKey = AionKeychain.read(account: StorageKeys.keychainAPIKey) ?? ""
            serverConfig = decoded
        } else {
            serverConfig.password = AionKeychain.read(account: StorageKeys.keychainPassword) ?? ""
            serverConfig.apiKey = AionKeychain.read(account: StorageKeys.keychainAPIKey) ?? ""
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
