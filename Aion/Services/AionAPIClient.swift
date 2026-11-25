import Foundation

enum AionAPIError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case authenticationFailed(String)
    case serverError(Int, String)
    case decodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Server URL is invalid. Check Settings → Aion API Connection."
        case .unauthorized:
            return "Session expired or not signed in. Please sign in to Aion."
        case .authenticationFailed(let message):
            return message
        case .serverError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingFailed:
            return "Could not decode response from Aion server."
        case .cancelled:
            return "Request cancelled."
        }
    }
}

/// Real-time events arriving over AionUi's `/ws` WebSocket or OpenAI/Demo streams.
enum AionRealtimeEvent: Sendable {
    case wsConnected
    case wsDisconnected
    case textDelta(conversationID: String, msgID: String?, text: String, replace: Bool, isUser: Bool)
    case thinkingDelta(conversationID: String, msgID: String?, text: String)
    case toolCall(conversationID: String, msgID: String?, callID: String?, name: String, detail: String, status: AionToolCall.Status)
    case turnCompleted(conversationID: String)
    case conversationListChanged
    case confirmationChanged(conversationID: String)
    case streamError(conversationID: String, message: String)
    case summaryCard(AionSummaryCard)
    case suggestions([String])
    case finished
}

/// Production-ready native Swift client for AionUi's real REST + WebSocket API (`https://aion.5nod.com/`),
/// plus OpenAI-Compatible SSE API and offline Demo Mode.
actor AionAPIClient {
    private let session: URLSession
    private var csrfToken: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsReceiveTask: Task<Void, Never>?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }

    // MARK: - CSRF & Cookie Helpers

    private func captureCSRFToken(from response: URLResponse, baseURL: URL) {
        if let http = response as? HTTPURLResponse,
           let headerFields = http.allHeaderFields as? [String: String],
           let url = http.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
                if cookie.name == "aionui-csrf-token" {
                    self.csrfToken = cookie.value.removingPercentEncoding ?? cookie.value
                }
            }
        }
        if let stored = HTTPCookieStorage.shared.cookies(for: baseURL) {
            if let csrfCookie = stored.first(where: { $0.name == "aionui-csrf-token" }) {
                self.csrfToken = csrfCookie.value.removingPercentEncoding ?? csrfCookie.value
            }
        }
    }

    private func ensureCSRFToken(baseURL: URL) async {
        if csrfToken != nil { return }
        if let stored = HTTPCookieStorage.shared.cookies(for: baseURL),
           let existing = stored.first(where: { $0.name == "aionui-csrf-token" }) {
            csrfToken = existing.value.removingPercentEncoding ?? existing.value
            return
        }
        // GET /api/auth/user sets the aionui-csrf-token cookie even on 401
        var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/user"))
        req.httpMethod = "GET"
        if let (_, resp) = try? await session.data(for: req) {
            captureCSRFToken(from: resp, baseURL: baseURL)
        }
    }

    private func unwrapData(_ jsonObject: Any) -> Any {
        if let dict = jsonObject as? [String: Any], let data = dict["data"] {
            return data
        }
        return jsonObject
    }

    // MARK: - Core AionUi HTTP Bridge (`so()`)

    func requestJSONPublic(
        method: String,
        path: String,
        body: Any? = nil,
        config: AionServerConfig
    ) async throws -> Any {
        try await requestJSON(method: method, path: path, body: body, config: config)
    }

    func parseConversationPublic(_ dict: [String: Any]) -> AionConversation? {
        parseConversation(dict)
    }

    func uploadMultipartFile(
        fileData: Data,
        fileName: String,
        mimeType: String,
        conversationRemoteID: String?,
        config: AionServerConfig
    ) async throws -> String {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }
        await ensureCSRFToken(baseURL: baseURL)

        let url = baseURL.appendingPathComponent("api/fs/upload")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let csrf = csrfToken, !csrf.isEmpty {
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        if let conversationRemoteID, !conversationRemoteID.isEmpty {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"conversation_id\"\r\n\r\n".utf8))
            body.append(Data("\(conversationRemoteID)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        captureCSRFToken(from: response, baseURL: baseURL)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw AionAPIError.serverError(code, msg)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uploadedPath = json["data"] as? String, !uploadedPath.isEmpty {
            return uploadedPath
        }
        throw AionAPIError.decodingFailed
    }

    private func requestJSON(
        method: String,
        path: String,
        body: Any? = nil,
        config: AionServerConfig,
        allowRefreshRetry: Bool = true
    ) async throws -> Any {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }

        let upper = method.uppercased()
        if !["GET", "HEAD", "OPTIONS"].contains(upper) {
            await ensureCSRFToken(baseURL: baseURL)
        }

        let fullURLString = path.hasPrefix("/") ? "\(baseURL.absoluteString)\(path)" : "\(baseURL.absoluteString)/\(path)"
        guard let url = URL(string: fullURLString) else {
            throw AionAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = upper
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        if !["GET", "HEAD", "OPTIONS"].contains(upper), let token = csrfToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "x-csrf-token")
        }

        let (data, response) = try await session.data(for: request)
        captureCSRFToken(from: response, baseURL: baseURL)

        guard let http = response as? HTTPURLResponse else {
            throw AionAPIError.decodingFailed
        }

        if http.statusCode == 401 && allowRefreshRetry && !path.hasPrefix("/login") && !path.hasPrefix("/api/auth/refresh") {
            if await refreshSession(config: config) {
                return try await requestJSON(method: method, path: path, body: body, config: config, allowRefreshRetry: false)
            }
            throw AionAPIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 {
                throw AionAPIError.unauthorized
            }
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = (dict["message"] as? String) ?? (dict["error"] as? String) {
                throw AionAPIError.serverError(http.statusCode, msg)
            }
            throw AionAPIError.serverError(http.statusCode, String(text.prefix(200)))
        }

        guard !data.isEmpty else { return [String: Any]() }
        let raw = try JSONSerialization.jsonObject(with: data)
        return unwrapData(raw)
    }

    // MARK: - Auth: Check Session, Login, Refresh, Logout

    func checkSession(config: AionServerConfig) async -> (state: AionConnectionState, user: AionUser?) {
        switch config.mode {
        case .demo:
            return (.demo, nil)

        case .openAICompatible:
            guard let baseURL = config.normalizedBaseURL else {
                return (.offline(reason: "Invalid API URL"), nil)
            }
            let start = Date()
            let modelsURL = baseURL.path.hasSuffix("/v1")
                ? baseURL.appendingPathComponent("models")
                : baseURL.appendingPathComponent("v1/models")
            var req = URLRequest(url: modelsURL)
            req.httpMethod = "GET"
            if !config.apiKey.isEmpty {
                req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (_, resp) = try await session.data(for: req)
                let ms = max(1, Int(Date().timeIntervalSince(start) * 1000))
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return (.connected(latencyMs: ms, username: "API"), nil)
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return (.offline(reason: "HTTP \(code)"), nil)
            } catch {
                return (.offline(reason: error.localizedDescription), nil)
            }

        case .aionWebUI:
            guard let baseURL = config.normalizedBaseURL else {
                return (.offline(reason: "Invalid server URL"), nil)
            }
            let start = Date()
            do {
                var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/user"))
                req.httpMethod = "GET"
                let (data, resp) = try await session.data(for: req)
                captureCSRFToken(from: resp, baseURL: baseURL)
                let ms = max(1, Int(Date().timeIntervalSince(start) * 1000))

                guard let http = resp as? HTTPURLResponse else {
                    return (.offline(reason: "No HTTP response"), nil)
                }
                if (200...299).contains(http.statusCode),
                   let parsed = parseUser(from: data) {
                    return (.connected(latencyMs: ms, username: parsed.username), parsed)
                }
                if http.statusCode == 401 {
                    // Try silent refresh first
                    if await refreshSession(config: config) {
                        let (retryData, retryResp) = try await session.data(for: req)
                        captureCSRFToken(from: retryResp, baseURL: baseURL)
                        if let retryHTTP = retryResp as? HTTPURLResponse,
                           (200...299).contains(retryHTTP.statusCode),
                           let user = parseUser(from: retryData) {
                            return (.connected(latencyMs: ms, username: user.username), user)
                        }
                    }
                    // If saved password exists, auto-login seamlessly
                    if !config.password.isEmpty {
                        let user = try await login(config: config)
                        let loginMs = max(1, Int(Date().timeIntervalSince(start) * 1000))
                        return (.connected(latencyMs: loginMs, username: user.username), user)
                    }
                    return (.needsLogin, nil)
                }
                return (.offline(reason: "HTTP \(http.statusCode)"), nil)
            } catch let apiErr as AionAPIError {
                return (.offline(reason: apiErr.localizedDescription), nil)
            } catch {
                return (.offline(reason: error.localizedDescription), nil)
            }
        }
    }

    func login(config: AionServerConfig) async throws -> AionUser {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }
        await ensureCSRFToken(baseURL: baseURL)

        var req = URLRequest(url: baseURL.appendingPathComponent("login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let csrf = csrfToken, !csrf.isEmpty {
            req.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }

        let payload: [String: Any] = [
            "username": config.username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": config.password,
            "remember": true
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        captureCSRFToken(from: resp, baseURL: baseURL)

        guard let http = resp as? HTTPURLResponse else {
            throw AionAPIError.decodingFailed
        }

        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if (200...299).contains(http.statusCode),
               (dict["success"] as? Bool ?? true),
               let user = parseUser(from: data) {
                return user
            }
            let message = (dict["message"] as? String) ?? (dict["error"] as? String) ?? "Invalid username or password"
            if http.statusCode == 403 {
                // Retry once with refreshed CSRF token
                csrfToken = nil
                await ensureCSRFToken(baseURL: baseURL)
                if let csrf = csrfToken {
                    req.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
                    let (retryData, retryResp) = try await session.data(for: req)
                    captureCSRFToken(from: retryResp, baseURL: baseURL)
                    if let retryHTTP = retryResp as? HTTPURLResponse,
                       (200...299).contains(retryHTTP.statusCode),
                       let user = parseUser(from: retryData) {
                        return user
                    }
                }
            }
            throw AionAPIError.authenticationFailed(message)
        }
        throw AionAPIError.authenticationFailed("Login failed (HTTP \(http.statusCode))")
    }

    func refreshSession(config: AionServerConfig) async -> Bool {
        guard let baseURL = config.normalizedBaseURL else { return false }
        await ensureCSRFToken(baseURL: baseURL)
        var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/refresh"))
        req.httpMethod = "POST"
        if let csrf = csrfToken, !csrf.isEmpty {
            req.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        captureCSRFToken(from: resp, baseURL: baseURL)
        return (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
    }

    func logout(config: AionServerConfig) async {
        disconnectWebSocket()
        if let baseURL = config.normalizedBaseURL {
            await ensureCSRFToken(baseURL: baseURL)
            var req = URLRequest(url: baseURL.appendingPathComponent("logout"))
            req.httpMethod = "POST"
            if let csrf = csrfToken {
                req.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
            }
            _ = try? await session.data(for: req)
            if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
                for c in cookies {
                    HTTPCookieStorage.shared.deleteCookie(c)
                }
            }
        }
        csrfToken = nil
    }

    private func parseUser(from data: Data) -> AionUser? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let candidate = (root["user"] as? [String: Any])
            ?? ((root["data"] as? [String: Any])?["user"] as? [String: Any])
            ?? (root["data"] as? [String: Any])
            ?? root

        guard let username = (candidate["username"] as? String) ?? (candidate["name"] as? String) else {
            return nil
        }
        let id = (candidate["id"] as? String) ?? (candidate["user_id"] as? String) ?? username
        let role = candidate["role"] as? String
        return AionUser(id: id, username: username, role: role)
    }

    // MARK: - Live AionUi REST Endpoints

    func fetchConversations(config: AionServerConfig, limit: Int = 50) async throws -> [AionConversation] {
        let raw = try await requestJSON(method: "GET", path: "/api/conversations?limit=\(limit)", config: config)
        let items: [[String: Any]]
        if let dict = raw as? [String: Any], let arr = dict["items"] as? [[String: Any]] {
            items = arr
        } else if let arr = raw as? [[String: Any]] {
            items = arr
        } else {
            items = []
        }

        return items.compactMap { parseConversation($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchMessages(conversationRemoteID: String, config: AionServerConfig, limit: Int = 100) async throws -> [AionMessage] {
        let encoded = conversationRemoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationRemoteID
        let raw = try await requestJSON(method: "GET", path: "/api/conversations/\(encoded)/messages?limit=\(limit)", config: config)

        let items: [[String: Any]]
        if let dict = raw as? [String: Any] {
            items = (dict["items"] as? [[String: Any]]) ?? (dict["messages"] as? [[String: Any]]) ?? []
        } else if let arr = raw as? [[String: Any]] {
            items = arr
        } else {
            items = []
        }

        var parsed: [AionMessage] = []
        for item in items {
            if let hidden = item["hidden"] as? Bool, hidden { continue }
            guard let msg = parseMessage(item) else { continue }
            // Merge consecutive assistant tool/thinking/text entries sharing the same msg_id if needed
            if let last = parsed.last,
               let msgID = msg.remoteMsgID,
               !msgID.isEmpty,
               last.remoteMsgID == msgID,
               last.role == msg.role {
                var merged = parsed.removeLast()
                if !msg.content.isEmpty {
                    merged.content = merged.content.isEmpty ? msg.content : "\(merged.content)\n\n\(msg.content)"
                }
                if !msg.toolCalls.isEmpty {
                    merged.toolCalls.append(contentsOf: msg.toolCalls)
                }
                parsed.append(merged)
            } else {
                parsed.append(msg)
            }
        }
        return parsed
    }

    func createConversation(
        name: String,
        assistantID: String?,
        config: AionServerConfig
    ) async throws -> AionConversation {
        var body: [String: Any] = ["name": name]
        if let assistantID, !assistantID.isEmpty {
            body["assistant"] = assistantID
        } else {
            body["type"] = "aionrs"
        }

        let raw = try await requestJSON(method: "POST", path: "/api/conversations", body: body, config: config)
        if let dict = raw as? [String: Any], let convo = parseConversation(dict) {
            return convo
        }
        throw AionAPIError.decodingFailed
    }

    func deleteConversation(remoteID: String, config: AionServerConfig) async throws {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        _ = try await requestJSON(method: "DELETE", path: "/api/conversations/\(encoded)", config: config)
    }

    func sendConversationMessage(
        remoteID: String,
        content: String,
        files: [String] = [],
        injectSkills: [String] = [],
        config: AionServerConfig
    ) async throws {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        var body: [String: Any] = ["content": content]
        if !files.isEmpty {
            body["files"] = files
        }
        if !injectSkills.isEmpty {
            body["inject_skills"] = injectSkills
        }
        _ = try await requestJSON(method: "POST", path: "/api/conversations/\(encoded)/messages", body: body, config: config)
    }

    func cancelConversation(remoteID: String, config: AionServerConfig) async {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        _ = try? await requestJSON(method: "POST", path: "/api/conversations/\(encoded)/cancel", body: [String: Any](), config: config)
    }

    func fetchAssistants(config: AionServerConfig) async throws -> [AionAssistant] {
        let raw = try await requestJSON(method: "GET", path: "/api/assistants", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any], let arr = dict["items"] as? [[String: Any]] {
            items = arr
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let name = (item["name"] as? String) ?? id
            let description = (item["description"] as? String) ?? ""
            let backend = (item["backend"] as? String) ?? (item["agent"] as? String) ?? "aion"
            let avatar = item["avatar"] as? String
            let enabled = (item["enabled"] as? Bool) ?? true
            return AionAssistant(id: id, name: name, description: description, backend: backend, avatar: avatar, enabled: enabled)
        }
    }

    func fetchSkills(config: AionServerConfig) async throws -> [AionSkill] {
        let raw = try await requestJSON(method: "GET", path: "/api/skills", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any] {
            items = (dict["skills"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        return items.compactMap { item in
            let name = (item["name"] as? String) ?? (item["id"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            let id = (item["id"] as? String) ?? name
            let desc = (item["description"] as? String) ?? "Aion workspace skill"
            let category = (item["source"] as? String) ?? (item["category"] as? String) ?? "Skill"
            let enabled = (item["enabled"] as? Bool) ?? true
            return AionSkill(
                id: id,
                name: name.replacingOccurrences(of: "-", with: " ").capitalized,
                summary: desc,
                iconName: iconForSkill(id),
                category: category.capitalized,
                samplePrompt: "Use the \(name) skill to help me with my current task.",
                isEnabled: enabled
            )
        }
    }

    func fetchCronJobs(config: AionServerConfig) async throws -> [AionCronTask] {
        let raw = try await requestJSON(method: "GET", path: "/api/cron/jobs", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any] {
            items = (dict["jobs"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let jobID = (item["id"] as? String) ?? (item["job_id"] as? String) else { return nil }
            let name = (item["name"] as? String) ?? "Scheduled Task"
            let enabled = (item["enabled"] as? Bool) ?? true
            let scheduleObj = item["schedule"] as? [String: Any]
            let expr = (scheduleObj?["expr"] as? String)
                ?? (item["schedule"] as? String)
                ?? "cron"
            let scheduleLabel = (item["schedule_description"] as? String)
                ?? (item["description"] as? String)
                ?? expr
            let target = item["target"] as? [String: Any]
            let payload = target?["payload"] as? [String: Any]
            let prompt = (payload?["text"] as? String)
                ?? (item["message"] as? String)
                ?? ""

            return AionCronTask(
                remoteJobID: jobID,
                name: name,
                scheduleExpression: expr,
                scheduleLabel: scheduleLabel.isEmpty ? expr : scheduleLabel,
                prompt: prompt,
                isActive: enabled,
                lastRunAt: parseDate(item["last_run_at"] ?? item["updated_at"])
            )
        }
    }

    func toggleCronJob(remoteJobID: String, enabled: Bool, config: AionServerConfig) async throws {
        let encoded = remoteJobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteJobID
        _ = try await requestJSON(
            method: "PUT",
            path: "/api/cron/jobs/\(encoded)",
            body: ["enabled": enabled],
            config: config
        )
    }

    func runCronJobNow(remoteJobID: String, config: AionServerConfig) async throws {
        let encoded = remoteJobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteJobID
        _ = try await requestJSON(method: "POST", path: "/api/cron/jobs/\(encoded)/run", body: [String: Any](), config: config)
    }

    func deleteCronJob(remoteJobID: String, config: AionServerConfig) async throws {
        let encoded = remoteJobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteJobID
        _ = try await requestJSON(method: "DELETE", path: "/api/cron/jobs/\(encoded)", config: config)
    }

    func createCronJob(
        name: String,
        cronExpr: String,
        prompt: String,
        conversationRemoteID: String?,
        config: AionServerConfig
    ) async throws {
        var body: [String: Any] = [
            "name": name,
            "schedule": [
                "kind": "cron",
                "expr": cronExpr,
                "tz": TimeZone.current.identifier
            ],
            "message": prompt,
            "created_by": "user",
            "enabled": true
        ]
        if let conversationRemoteID {
            body["conversation_id"] = conversationRemoteID
        }
        _ = try await requestJSON(method: "POST", path: "/api/cron/jobs", body: body, config: config)
    }

    func searchMessages(keyword: String, config: AionServerConfig) async throws -> [AionSearchHit] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let raw = try await requestJSON(method: "GET", path: "/api/messages/search?keyword=\(encoded)&page=1&page_size=30", config: config)
        let items: [[String: Any]]
        if let dict = raw as? [String: Any], let arr = dict["items"] as? [[String: Any]] {
            items = arr
        } else if let arr = raw as? [[String: Any]] {
            items = arr
        } else {
            items = []
        }

        return items.compactMap { item in
            let convo = item["conversation"] as? [String: Any]
            guard let convoID = convo?["id"] as? String else { return nil }
            let title = (convo?["name"] as? String) ?? "Conversation"
            let preview = (item["preview_text"] as? String) ?? ""
            let msgID = (item["message_id"] as? String) ?? UUID().uuidString
            let created = parseDate(item["message_created_at"]) ?? Date()
            return AionSearchHit(
                id: "\(convoID)-\(msgID)",
                conversationRemoteID: convoID,
                conversationTitle: title,
                previewText: preview,
                createdAt: created
            )
        }
    }

    // MARK: - Persistent Real-Time WebSocket (`wss://aion.5nod.com/ws`)

    func connectWebSocket(
        config: AionServerConfig,
        onEvent: @escaping @Sendable (AionRealtimeEvent) -> Void
    ) {
        disconnectWebSocket()
        guard config.mode == .aionWebUI, let wsURL = config.webSocketURL else { return }

        wsReceiveTask = Task { [weak self] in
            var backoffSeconds: Double = 1.0
            while !Task.isCancelled {
                guard let self else { break }
                var req = URLRequest(url: wsURL)
                if !config.apiKey.isEmpty {
                    req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                }

                let socket = await self.openWebSocketTask(request: req)
                onEvent(.wsConnected)

                do {
                    while !Task.isCancelled {
                        let frame = try await socket.receive()
                        backoffSeconds = 1.0
                        let text: String?
                        switch frame {
                        case .string(let str): text = str
                        case .data(let data): text = String(data: data, encoding: .utf8)
                        @unknown default: text = nil
                        }
                        if let text {
                            await self.handleWebSocketFrame(text, onEvent: onEvent)
                        }
                    }
                } catch {
                    onEvent(.wsDisconnected)
                }

                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2.0, 20.0)
            }
        }
    }

    func disconnectWebSocket() {
        wsReceiveTask?.cancel()
        wsReceiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func openWebSocketTask(request: URLRequest) -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        return task
    }

    private func handleWebSocketFrame(
        _ raw: String,
        onEvent: @escaping @Sendable (AionRealtimeEvent) -> Void
    ) async {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let name = (json["name"] as? String) ?? (json["event"] as? String) ?? ""
        let payload = (json["data"] as? [String: Any]) ?? (json["payload"] as? [String: Any]) ?? [:]

        // Official AionUi heartbeat ping -> pong
        if name == "ping" {
            let pong: [String: Any] = [
                "name": "pong",
                "data": ["timestamp": Int(Date().timeIntervalSince1970 * 1000)]
            ]
            if let socket = self.webSocketTask,
               let pongData = try? JSONSerialization.data(withJSONObject: pong),
               let pongStr = String(data: pongData, encoding: .utf8) {
                try? await socket.send(.string(pongStr))
            }
            return
        }

        if name == "conversation.listChanged" {
            onEvent(.conversationListChanged)
            return
        }

        if name == "confirmation.remove" || name == "confirmation.add" {
            if let convoID = payload["conversation_id"] as? String {
                onEvent(.confirmationChanged(conversationID: convoID))
            }
            return
        }

        if name == "turn.completed" {
            if let sessionID = (payload["session_id"] as? String) ?? (payload["conversation_id"] as? String) {
                onEvent(.turnCompleted(conversationID: sessionID))
            }
            return
        }

        if name == "message.stream" {
            guard let convoID = payload["conversation_id"] as? String else { return }
            let type = (payload["type"] as? String) ?? ""
            let msgID = payload["msg_id"] as? String
            let replace = (payload["replace"] as? Bool) ?? false

            switch type {
            case "content", "text", "user_content":
                let extracted = extractTextContent(payload["data"])
                if !extracted.isEmpty {
                    let isUser = (type == "user_content") || ((payload["position"] as? String) == "right")
                    onEvent(.textDelta(conversationID: convoID, msgID: msgID, text: extracted, replace: replace, isUser: isUser))
                }

            case "thinking", "thought":
                let extracted = extractTextContent(payload["data"])
                if !extracted.isEmpty {
                    onEvent(.thinkingDelta(conversationID: convoID, msgID: msgID, text: extracted))
                }

            case "tool_call", "acp_tool_call", "tool_group":
                if let tool = extractToolCall(from: payload["data"]) {
                    onEvent(.toolCall(
                        conversationID: convoID,
                        msgID: msgID,
                        callID: tool.callID,
                        name: tool.name,
                        detail: tool.detail,
                        status: tool.status
                    ))
                }

            case "permission", "ask":
                onEvent(.confirmationChanged(conversationID: convoID))

            case "finish":
                onEvent(.turnCompleted(conversationID: convoID))

            case "error":
                let errText = extractTextContent(payload["data"])
                onEvent(.streamError(conversationID: convoID, message: errText.isEmpty ? "Agent error" : errText))

            default:
                break
            }
        }
    }

    // MARK: - OpenAI-Compatible & Demo Streaming

    func streamFallbackReply(
        prompt: String,
        history: [AionMessage],
        modelID: String,
        activeSkill: AionSkill?,
        config: AionServerConfig
    ) -> AsyncThrowingStream<AionRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch config.mode {
                    case .demo:
                        try await self.runDemoStream(prompt: prompt, activeSkill: activeSkill, continuation: continuation)
                    case .openAICompatible:
                        try await self.runOpenAIStream(prompt: prompt, history: history, modelID: modelID, config: config, continuation: continuation)
                    case .aionWebUI:
                        break
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runOpenAIStream(
        prompt: String,
        history: [AionMessage],
        modelID: String,
        config: AionServerConfig,
        continuation: AsyncThrowingStream<AionRealtimeEvent, Error>.Continuation
    ) async throws {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }
        let chatURL = baseURL.path.hasSuffix("/v1")
            ? baseURL.appendingPathComponent("chat/completions")
            : baseURL.appendingPathComponent("v1/chat/completions")

        var req = URLRequest(url: chatURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let formattedHistory: [[String: String]] = history.suffix(12).map {
            ["role": $0.role.rawValue, "content": $0.content]
        } + [["role": "user", "content": prompt]]

        let chosenModel = config.customModelName.isEmpty ? modelID : config.customModelName
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": chosenModel,
            "stream": true,
            "messages": formattedHistory
        ])

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw AionAPIError.decodingFailed }
        guard (200...299).contains(http.statusCode) else {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 240 { break }
            }
            throw AionAPIError.serverError(http.statusCode, errBody)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let jsonData = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            continuation.yield(.textDelta(conversationID: "openai", msgID: nil, text: content, replace: false, isUser: false))
        }
    }

    private func runDemoStream(
        prompt: String,
        activeSkill: AionSkill?,
        continuation: AsyncThrowingStream<AionRealtimeEvent, Error>.Continuation
    ) async throws {
        if let skill = activeSkill {
            continuation.yield(.toolCall(conversationID: "demo", msgID: nil, callID: skill.id, name: skill.id, detail: "Running \(skill.name)...", status: .running))
            try await Task.sleep(for: .milliseconds(450))
            continuation.yield(.toolCall(conversationID: "demo", msgID: nil, callID: skill.id, name: skill.id, detail: "\(skill.name) completed", status: .completed))
        }
        let reply = "You are currently in offline **Demo Mode**. Switch to **AionUi Remote** in Settings and sign in to `https://aion.5nod.com` to chat with your real live Aion agents, skills, and cron jobs."
        for (i, token) in reply.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            try Task.checkCancellation()
            let piece = i == 0 ? String(token) : " " + String(token)
            continuation.yield(.textDelta(conversationID: "demo", msgID: nil, text: piece, replace: false, isUser: false))
            try await Task.sleep(for: .milliseconds(22))
        }
        continuation.yield(.suggestions(["Open Settings", "Connect to aion.5nod.com"]))
    }

    // MARK: - JSON Parsers

    private func parseConversation(_ dict: [String: Any]) -> AionConversation? {
        guard let remoteID = dict["id"] as? String else { return nil }
        let title = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (title?.isEmpty == false) ? title! : "Untitled Thread"
        let type = dict["type"] as? String
        let modelObj = dict["model"] as? [String: Any]
        let modelID = (modelObj?["use_model"] as? String) ?? (modelObj?["model"] as? String) ?? "aion-default"
        let extra = dict["extra"] as? [String: Any]
        let assistantID = (dict["assistant"] as? String) ?? (extra?["assistantId"] as? String) ?? (extra?["assistant_id"] as? String)
        let updated = parseDate(dict["modifyTime"] ?? dict["updated_at"] ?? dict["createTime"] ?? dict["created_at"]) ?? Date()

        return AionConversation(
            remoteID: remoteID,
            title: displayTitle,
            iconName: iconForConversationType(type),
            modelID: modelID,
            conversationType: type,
            assistantID: assistantID,
            updatedAt: updated,
            messages: [],
            hasLoadedMessages: false
        )
    }

    private func parseMessage(_ dict: [String: Any]) -> AionMessage? {
        let type = (dict["type"] as? String) ?? "text"
        let position = (dict["position"] as? String) ?? "left"
        let msgID = (dict["msg_id"] as? String) ?? (dict["id"] as? String)
        let created = parseDate(dict["created_at"] ?? dict["createdAt"] ?? dict["createTime"]) ?? Date()
        let isUser = (position == "right") || (type == "user_content")

        switch type {
        case "text", "content", "user_content", "tips":
            let text = extractTextContent(dict["content"] ?? dict["data"])
            guard !text.isEmpty else { return nil }
            return AionMessage(
                remoteMsgID: msgID,
                role: isUser ? .user : .assistant,
                content: text,
                createdAt: created
            )

        case "thinking", "thought":
            let text = extractTextContent(dict["content"] ?? dict["data"])
            guard !text.isEmpty else { return nil }
            return AionMessage(
                remoteMsgID: msgID,
                role: .assistant,
                content: "",
                thinking: text,
                createdAt: created
            )

        case "tool_call", "acp_tool_call", "tool_group":
            if let tool = extractToolCall(from: dict["content"] ?? dict["data"]) {
                return AionMessage(
                    remoteMsgID: msgID,
                    role: .assistant,
                    content: "",
                    createdAt: created,
                    toolCalls: [tool]
                )
            }
            return nil

        default:
            let fallbackText = extractTextContent(dict["content"] ?? dict["data"])
            guard !fallbackText.isEmpty else { return nil }
            return AionMessage(
                remoteMsgID: msgID,
                role: isUser ? .user : .assistant,
                content: fallbackText,
                createdAt: created
            )
        }
    }

    private func extractTextContent(_ raw: Any?) -> String {
        if let str = raw as? String {
            return str
        }
        if let dict = raw as? [String: Any] {
            if let inner = dict["content"] as? String { return inner }
            if let inner = dict["text"] as? String { return inner }
            if let inner = dict["message"] as? String { return inner }
            if let nested = dict["content"] as? [String: Any], let inner = nested["content"] as? String {
                return inner
            }
        }
        return ""
    }

    private func extractToolCall(from raw: Any?) -> AionToolCall? {
        if let arr = raw as? [[String: Any]], let first = arr.first {
            return extractToolCall(from: first)
        }
        guard let dict = raw as? [String: Any] else { return nil }
        let update = (dict["update"] as? [String: Any]) ?? dict
        let name = (update["title"] as? String)
            ?? (update["name"] as? String)
            ?? (dict["name"] as? String)
            ?? (update["kind"] as? String)
            ?? "tool"
        let callID = (update["toolCallId"] as? String) ?? (dict["callId"] as? String) ?? (dict["id"] as? String)
        let rawStatus = ((update["status"] as? String) ?? (dict["status"] as? String) ?? "completed").lowercased()
        let status: AionToolCall.Status
        if rawStatus.contains("run") || rawStatus.contains("pending") || rawStatus.contains("progress") {
            status = .running
        } else if rawStatus.contains("err") || rawStatus.contains("fail") {
            status = .failed
        } else {
            status = .completed
        }
        let detail = (update["description"] as? String)
            ?? (update["kind"] as? String)
            ?? (status == .running ? "Running..." : "Completed")
        return AionToolCall(callID: callID, name: name, detail: detail, status: status)
    }

    private func parseDate(_ raw: Any?) -> Date? {
        if let ms = raw as? Double {
            return ms > 10_000_000_000 ? Date(timeIntervalSince1970: ms / 1000.0) : Date(timeIntervalSince1970: ms)
        }
        if let ms = raw as? Int {
            let d = Double(ms)
            return d > 10_000_000_000 ? Date(timeIntervalSince1970: d / 1000.0) : Date(timeIntervalSince1970: d)
        }
        if let str = raw as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: str)
        }
        return nil
    }

    private func iconForConversationType(_ type: String?) -> String {
        switch type?.lowercased() {
        case "acp": return "terminal.fill"
        case "gemini": return "sparkles"
        case "aionrs": return "cpu.fill"
        default: return "bubble.left.fill"
        }
    }

    private func iconForSkill(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("office") || lower.contains("doc") { return "doc.richtext.fill" }
        if lower.contains("cron") || lower.contains("schedule") { return "clock.badge.checkmark.fill" }
        if lower.contains("config") { return "slider.horizontal.3" }
        if lower.contains("session") || lower.contains("message") { return "arrow.triangle.2.circlepath.circle.fill" }
        if lower.contains("conversation") { return "bubble.left.and.text.bubble.right.fill" }
        return "wand.and.stars"
    }
}
