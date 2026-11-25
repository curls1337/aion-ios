import Foundation

enum AionAPIError: LocalizedError, Sendable {
    case invalidURL
    case authenticationFailed(String)
    case serverError(Int, String)
    case decodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Server URL is invalid. Check Settings → Server Connection."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .serverError(let code, let body):
            return "Server returned HTTP \(code): \(body)"
        case .decodingFailed:
            return "Could not decode response from server."
        case .cancelled:
            return "Request cancelled."
        }
    }
}

/// Chunk emitted during live token streaming or tool status updates.
enum AionStreamEvent: Sendable {
    case delta(String)
    case toolStarted(name: String, detail: String)
    case toolCompleted(name: String, detail: String, duration: Double)
    case summaryCard(AionSummaryCard)
    case suggestions([String])
    case finished
}

/// Native async/await networking client supporting:
/// 1) AionUi WebUI API + WebSocket Bridge (`:25808`)
/// 2) OpenAI-Compatible SSE Streaming (`/v1/chat/completions`)
/// 3) Built-in Interactive Demo Simulator
actor AionAPIClient {
    private let session: URLSession
    private var authToken: String?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Test & Login

    func testConnection(config: AionServerConfig) async -> AionConnectionState {
        switch config.mode {
        case .demo:
            return .demo

        case .aionWebUI:
            guard let baseURL = config.normalizedBaseURL else {
                return .offline(reason: "Invalid server URL")
            }
            let start = Date()
            do {
                // Attempt login first if credentials are provided
                if !config.password.isEmpty {
                    try await authenticateAionWebUI(baseURL: baseURL, config: config)
                }
                var request = URLRequest(url: baseURL.appendingPathComponent("api/health"))
                request.httpMethod = "GET"
                applyAuthHeaders(to: &request, config: config)

                let (_, response) = try await session.data(for: request)
                let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
                if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                    return .connected(latencyMs: latency)
                }
                return .offline(reason: "Unexpected server response")
            } catch {
                // Fallback probe on root URL in case /api/health is not mounted
                do {
                    var rootReq = URLRequest(url: baseURL)
                    rootReq.httpMethod = "GET"
                    let (_, resp) = try await session.data(for: rootReq)
                    let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
                    if let http = resp as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                        return .connected(latencyMs: latency)
                    }
                    return .offline(reason: error.localizedDescription)
                } catch {
                    return .offline(reason: error.localizedDescription)
                }
            }

        case .openAICompatible:
            guard let baseURL = config.normalizedBaseURL else {
                return .offline(reason: "Invalid API URL")
            }
            let start = Date()
            let modelsURL = baseURL.path.hasSuffix("/v1")
                ? baseURL.appendingPathComponent("models")
                : baseURL.appendingPathComponent("v1/models")
            var request = URLRequest(url: modelsURL)
            request.httpMethod = "GET"
            applyAuthHeaders(to: &request, config: config)

            do {
                let (_, response) = try await session.data(for: request)
                let latency = max(1, Int(Date().timeIntervalSince(start) * 1000))
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return .connected(latencyMs: latency)
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .offline(reason: "HTTP \(status)")
            } catch {
                return .offline(reason: error.localizedDescription)
            }
        }
    }

    private func authenticateAionWebUI(baseURL: URL, config: AionServerConfig) async throws {
        let loginURL = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "username": config.username.isEmpty ? "admin" : config.username,
            "password": config.password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        if (200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String {
                    self.authToken = token
                } else if let dataObj = json["data"] as? [String: Any], let token = dataObj["token"] as? String {
                    self.authToken = token
                }
            }
        } else if http.statusCode == 401 || http.statusCode == 403 {
            throw AionAPIError.authenticationFailed("Invalid credentials (\(http.statusCode))")
        }
    }

    private func applyAuthHeaders(to request: inout URLRequest, config: AionServerConfig) {
        let token = !config.apiKey.isEmpty ? config.apiKey : (authToken ?? "")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Streaming Chat

    func streamReply(
        prompt: String,
        history: [AionMessage],
        modelID: String,
        activeSkill: AionSkill?,
        config: AionServerConfig
    ) -> AsyncThrowingStream<AionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch config.mode {
                    case .demo:
                        try await self.runDemoStream(
                            prompt: prompt,
                            activeSkill: activeSkill,
                            continuation: continuation
                        )
                    case .openAICompatible:
                        try await self.runOpenAIStream(
                            prompt: prompt,
                            history: history,
                            modelID: modelID,
                            config: config,
                            continuation: continuation
                        )
                    case .aionWebUI:
                        try await self.runAionWebUIStream(
                            prompt: prompt,
                            history: history,
                            modelID: modelID,
                            activeSkill: activeSkill,
                            config: config,
                            continuation: continuation
                        )
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - AionUi WebUI WebSocket Bridge Stream

    private func runAionWebUIStream(
        prompt: String,
        history: [AionMessage],
        modelID: String,
        activeSkill: AionSkill?,
        config: AionServerConfig,
        continuation: AsyncThrowingStream<AionStreamEvent, Error>.Continuation
    ) async throws {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }

        if authToken == nil && !config.password.isEmpty {
            try await authenticateAionWebUI(baseURL: baseURL, config: config)
        }

        // First attempt native WebSocket bridge `/ws` using AionUi { name, data } envelope
        if let wsURL = config.webSocketURL {
            var wsRequest = URLRequest(url: wsURL)
            applyAuthHeaders(to: &wsRequest, config: config)

            let socket = session.webSocketTask(with: wsRequest)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            let requestID = UUID().uuidString
            var dataPayload: [String: Any] = [
                "requestId": requestID,
                "content": prompt,
                "model": modelID
            ]
            if let skillID = activeSkill?.id {
                dataPayload["skill"] = skillID
            }
            let envelope: [String: Any] = [
                "name": "conversation.sendMessage",
                "data": dataPayload
            ]

            do {
                let payloadData = try JSONSerialization.data(withJSONObject: envelope)
                if let text = String(data: payloadData, encoding: .utf8) {
                    try await socket.send(.string(text))
                }

                var receivedAny = false
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    switch message {
                    case .string(let raw):
                        if let parsed = parseAionBridgeFrame(raw) {
                            receivedAny = true
                            switch parsed {
                            case .finished:
                                return
                            default:
                                continuation.yield(parsed)
                            }
                        }
                    case .data(let data):
                        if let raw = String(data: data, encoding: .utf8),
                           let parsed = parseAionBridgeFrame(raw) {
                            receivedAny = true
                            switch parsed {
                            case .finished:
                                return
                            default:
                                continuation.yield(parsed)
                            }
                        }
                    @unknown default:
                        break
                    }
                }
                if receivedAny { return }
            } catch {
                // Fall back to HTTP OpenAI-compatible or REST chat endpoint if /ws bridge differs
                try await runOpenAIStream(
                    prompt: prompt,
                    history: history,
                    modelID: modelID,
                    config: config,
                    continuation: continuation
                )
                return
            }
        }
    }

    private func parseAionBridgeFrame(_ raw: String) -> AionStreamEvent? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = (json["name"] as? String) ?? (json["type"] as? String) ?? ""
        let payload = json["data"] as? [String: Any]

        if name.contains("done") || name.contains("finish") || name.contains("complete") {
            return .finished
        }

        if let delta = payload?["delta"] as? String ?? payload?["content"] as? String ?? json["delta"] as? String {
            return .delta(delta)
        }

        if name.contains("tool"), let toolName = payload?["tool"] as? String {
            let detail = (payload?["detail"] as? String) ?? "Running..."
            return .toolStarted(name: toolName, detail: detail)
        }

        return nil
    }

    // MARK: - OpenAI-Compatible SSE Stream

    private func runOpenAIStream(
        prompt: String,
        history: [AionMessage],
        modelID: String,
        config: AionServerConfig,
        continuation: AsyncThrowingStream<AionStreamEvent, Error>.Continuation
    ) async throws {
        guard let baseURL = config.normalizedBaseURL else {
            throw AionAPIError.invalidURL
        }

        let chatURL = baseURL.path.hasSuffix("/v1")
            ? baseURL.appendingPathComponent("chat/completions")
            : baseURL.appendingPathComponent("v1/chat/completions")

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthHeaders(to: &request, config: config)

        let formattedHistory: [[String: String]] = history.suffix(12).map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        } + [["role": "user", "content": prompt]]

        let chosenModel = config.customModelName.isEmpty ? modelID : config.customModelName
        let body: [String: Any] = [
            "model": chosenModel,
            "stream": true,
            "messages": formattedHistory
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AionAPIError.decodingFailed
        }
        guard (200...299).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 240 { break }
            }
            throw AionAPIError.serverError(http.statusCode, errorBody)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }
            guard let jsonData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            continuation.yield(.delta(content))
        }
    }

    // MARK: - Smooth Interactive Demo Stream

    private func runDemoStream(
        prompt: String,
        activeSkill: AionSkill?,
        continuation: AsyncThrowingStream<AionStreamEvent, Error>.Continuation
    ) async throws {
        let lower = prompt.lowercased()

        if let skill = activeSkill {
            continuation.yield(.toolStarted(name: skill.id, detail: "Executing \(skill.name)..."))
            try await Task.sleep(for: .milliseconds(480))
            continuation.yield(.toolCompleted(name: skill.id, detail: "\(skill.name) completed", duration: 0.48))
        } else if lower.contains("report") || lower.contains("summary") || lower.contains("ringkas") {
            continuation.yield(.toolStarted(name: "officecli", detail: "Analyzing attached workspace documents..."))
            try await Task.sleep(for: .milliseconds(520))
            continuation.yield(.toolCompleted(name: "officecli", detail: "Parsed workspace brief", duration: 0.52))
        }

        let reply: String
        let card: AionSummaryCard?
        let suggestions: [String]

        if lower.contains("report") || lower.contains("summary") || lower.contains("ringkas") {
            reply = "Here is a crisp breakdown based on your latest workspace context. Everything is synced and ready for sharing."
            card = AionSummaryCard(
                title: "Executive Summary",
                bullets: [
                    "Native SwiftUI client delivers 120Hz ProMotion scrolling",
                    "API streaming latency averaged 24ms over Tailscale",
                    "All 3 scheduled cron workflows executed without error"
                ],
                attachmentName: "aion-summary.docx"
            )
            suggestions = ["Draft email", "Key risks", "Share"]
        } else if lower.contains("code") || lower.contains("swift") || lower.contains("api") {
            reply = """
            Here is a clean Swift async/await snippet for connecting directly to your AionUi host:

            ```swift
            let url = URL(string: "http://100.64.0.12:25808/ws")!
            let socket = URLSession.shared.webSocketTask(with: url)
            socket.resume()
            ```

            Open **Settings → Server Connection** anytime to switch from Demo Mode to your live AionUi server or OpenAI-compatible API.
            """
            card = nil
            suggestions = ["Test latency", "Show WebSocket format", "Configure Tailscale"]
        } else {
            reply = "Got it — I've queued **\"\(prompt)\"** in your Aion workspace. Connect your live AionUi host in **Settings** (`AionUi --webui --remote`) to run real agents, local skills, and scheduled cron jobs directly from your iPhone."
            card = nil
            suggestions = ["Connect live server", "Run a skill", "Create schedule"]
        }

        // Stream word-by-word at natural reading cadence
        let tokens = reply.split(separator: " ", omittingEmptySubsequences: false)
        for (index, token) in tokens.enumerated() {
            try Task.checkCancellation()
            let piece = index == 0 ? String(token) : " " + String(token)
            continuation.yield(.delta(piece))
            try await Task.sleep(for: .milliseconds(26))
        }

        if let card {
            continuation.yield(.summaryCard(card))
        }
        continuation.yield(.suggestions(suggestions))
    }
}
