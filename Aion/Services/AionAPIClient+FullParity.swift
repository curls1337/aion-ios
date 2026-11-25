import Foundation

/// Full Web-Parity REST extensions on `AionAPIClient` covering:
/// - Conversation pagination, rename, reset, confirmations, workspace explorer, slash commands, multipart file upload
/// - Assistants CRUD + rules editor
/// - Agents management + health checks
/// - Model Providers management
/// - MCP Servers management + connection testing
/// - Skills inspection + rescan + delete
/// - Server Settings & System Info
extension AionAPIClient {
    // MARK: - Paginated Conversations & Actions

    func fetchConversationsPage(
        config: AionServerConfig,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> (items: [AionConversation], nextCursor: String?) {
        var path = "/api/conversations?limit=\(limit)"
        if let cursor, !cursor.isEmpty,
           let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }

        let raw = try await requestJSONPublic(method: "GET", path: path, config: config)
        let rawItems: [[String: Any]]
        var nextCursor: String?

        if let dict = raw as? [String: Any] {
            rawItems = (dict["items"] as? [[String: Any]]) ?? []
            nextCursor = (dict["next_cursor"] as? String) ?? (dict["nextCursor"] as? String) ?? (dict["cursor"] as? String)
            if let hasMore = dict["has_more"] as? Bool, !hasMore {
                nextCursor = nil
            }
        } else if let arr = raw as? [[String: Any]] {
            rawItems = arr
        } else {
            rawItems = []
        }

        let parsed = rawItems.compactMap { parseConversationPublic($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return (parsed, nextCursor)
    }

    func renameConversation(remoteID: String, newName: String, config: AionServerConfig) async throws {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        _ = try await requestJSONPublic(
            method: "PATCH",
            path: "/api/conversations/\(encoded)",
            body: ["name": newName],
            config: config
        )
    }

    func resetConversation(remoteID: String, config: AionServerConfig) async throws {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        _ = try await requestJSONPublic(
            method: "POST",
            path: "/api/conversations/\(encoded)/reset",
            body: [String: Any](),
            config: config
        )
    }

    // MARK: - Confirmations / Tool Approvals

    func fetchConfirmations(remoteID: String, config: AionServerConfig) async throws -> [AionConfirmationItem] {
        let encoded = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        let raw = try await requestJSONPublic(method: "GET", path: "/api/conversations/\(encoded)/confirmations", config: config)
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any], let arr = dict["items"] as? [[String: Any]] {
            list = arr
        } else {
            list = []
        }

        return list.compactMap { item in
            guard let callID = (item["callId"] as? String) ?? (item["call_id"] as? String) ?? (item["id"] as? String) else {
                return nil
            }
            let msgID = (item["msg_id"] as? String) ?? (item["msgId"] as? String)
            let title = (item["title"] as? String) ?? (item["action"] as? String) ?? "Tool Approval Required"
            let desc = (item["description"] as? String) ?? (item["command"] as? String) ?? ""
            var options: [AionConfirmationOption] = []
            if let rawOpts = item["options"] as? [[String: Any]] {
                for opt in rawOpts {
                    let val = (opt["value"] as? String) ?? (opt["key"] as? String) ?? (opt["id"] as? String) ?? "allow"
                    let label = (opt["label"] as? String) ?? val.capitalized
                    let lower = val.lowercased()
                    options.append(AionConfirmationOption(
                        id: val,
                        label: label,
                        isDestructive: lower.contains("deny") || lower.contains("cancel") || lower.contains("reject"),
                        isAlwaysAllow: lower.contains("always")
                    ))
                }
            }
            if options.isEmpty {
                options = [
                    AionConfirmationOption(id: "proceed_once", label: "Allow Once", isDestructive: false, isAlwaysAllow: false),
                    AionConfirmationOption(id: "proceed_always", label: "Always Allow", isDestructive: false, isAlwaysAllow: true),
                    AionConfirmationOption(id: "cancel", label: "Deny", isDestructive: true, isAlwaysAllow: false)
                ]
            }
            return AionConfirmationItem(id: callID, msgID: msgID, title: title, description: desc, options: options)
        }
    }

    func respondConfirmation(
        remoteID: String,
        callID: String,
        msgID: String?,
        choiceValue: String,
        alwaysAllow: Bool,
        config: AionServerConfig
    ) async throws {
        let encConvo = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        let encCall = callID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? callID
        var body: [String: Any] = [
            "data": choiceValue,
            "always_allow": alwaysAllow
        ]
        if let msgID { body["msg_id"] = msgID }
        _ = try await requestJSONPublic(
            method: "POST",
            path: "/api/conversations/\(encConvo)/confirmations/\(encCall)/confirm",
            body: body,
            config: config
        )
    }

    // MARK: - Workspace Files & Multipart File Upload

    func fetchWorkspaceFiles(remoteID: String, subPath: String = "", config: AionServerConfig) async throws -> [AionWorkspaceFile] {
        let encConvo = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        let encPath = subPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let raw = try await requestJSONPublic(
            method: "GET",
            path: "/api/conversations/\(encConvo)/workspace?path=\(encPath)",
            config: config
        )

        let rawNodes: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            rawNodes = arr
        } else if let dict = raw as? [String: Any] {
            rawNodes = (dict["children"] as? [[String: Any]])
                ?? (dict["items"] as? [[String: Any]])
                ?? (dict["files"] as? [[String: Any]])
                ?? []
        } else {
            rawNodes = []
        }

        return rawNodes.compactMap { node in
            guard let name = node["name"] as? String else { return nil }
            let fullPath = (node["fullPath"] as? String)
                ?? (node["relativePath"] as? String)
                ?? (node["path"] as? String)
                ?? name
            let isDir = (node["isDir"] as? Bool)
                ?? (node["isDirectory"] as? Bool)
                ?? ((node["type"] as? String) == "directory")
            let size = node["size"] as? Int
            return AionWorkspaceFile(id: fullPath, name: name, path: fullPath, isDirectory: isDir, sizeBytes: size)
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func readWorkspaceFile(path: String, config: AionServerConfig) async throws -> String {
        let raw = try await requestJSONPublic(
            method: "POST",
            path: "/api/fs/read",
            body: ["path": path],
            config: config
        )
        if let str = raw as? String { return str }
        if let dict = raw as? [String: Any] {
            return (dict["content"] as? String) ?? (dict["data"] as? String) ?? ""
        }
        return ""
    }

    func uploadFile(
        fileData: Data,
        fileName: String,
        mimeType: String,
        conversationRemoteID: String?,
        config: AionServerConfig
    ) async throws -> String {
        try await uploadMultipartFile(
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            conversationRemoteID: conversationRemoteID,
            config: config
        )
    }

    func fetchSlashCommands(remoteID: String, config: AionServerConfig) async throws -> [AionSlashCommand] {
        let encConvo = remoteID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remoteID
        let raw = try await requestJSONPublic(method: "GET", path: "/api/conversations/\(encConvo)/slash-commands", config: config)
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any], let arr = dict["commands"] as? [[String: Any]] {
            list = arr
        } else {
            list = []
        }

        return list.compactMap { item in
            guard let name = (item["name"] as? String) ?? (item["command"] as? String) else { return nil }
            let clean = name.hasPrefix("/") ? name : "/\(name)"
            let desc = (item["description"] as? String) ?? ""
            return AionSlashCommand(id: clean, name: clean, description: desc)
        }
    }

    // MARK: - Assistants CRUD & Rules

    func setAssistantEnabled(id: String, enabled: Bool, config: AionServerConfig) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestJSONPublic(
            method: "PATCH",
            path: "/api/assistants/\(enc)/state",
            body: ["enabled": enabled],
            config: config
        )
    }

    func readAssistantRule(assistantID: String, config: AionServerConfig) async throws -> String {
        let raw = try await requestJSONPublic(
            method: "POST",
            path: "/api/skills/assistant-rule/read",
            body: ["assistant_id": assistantID],
            config: config
        )
        if let str = raw as? String { return str }
        if let dict = raw as? [String: Any] {
            return (dict["content"] as? String) ?? (dict["rule"] as? String) ?? ""
        }
        return ""
    }

    func writeAssistantRule(assistantID: String, content: String, config: AionServerConfig) async throws {
        _ = try await requestJSONPublic(
            method: "POST",
            path: "/api/skills/assistant-rule/write",
            body: ["assistant_id": assistantID, "content": content],
            config: config
        )
    }

    // MARK: - Managed Agents

    func fetchManagedAgents(config: AionServerConfig) async throws -> [AionManagedAgent] {
        let raw = try await requestJSONPublic(method: "GET", path: "/api/agents/management", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any] {
            items = (dict["agents"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let id = (item["id"] as? String) ?? (item["backend"] as? String) else { return nil }
            let name = (item["name"] as? String) ?? id.capitalized
            let backend = (item["backend"] as? String) ?? id
            let command = (item["command"] as? String) ?? (item["cliPath"] as? String)
            let enabled = (item["enabled"] as? Bool) ?? true
            let installed = (item["installed"] as? Bool) ?? (item["available"] as? Bool) ?? true
            let health = item["status"] as? String
            return AionManagedAgent(
                id: id,
                name: name,
                backend: backend,
                command: command,
                enabled: enabled,
                installed: installed,
                healthStatus: health
            )
        }
    }

    func setManagedAgentEnabled(id: String, enabled: Bool, config: AionServerConfig) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestJSONPublic(
            method: "PATCH",
            path: "/api/agents/\(enc)/enabled",
            body: ["enabled": enabled],
            config: config
        )
    }

    func checkManagedAgentHealth(id: String, config: AionServerConfig) async throws -> String {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let raw = try await requestJSONPublic(
            method: "POST",
            path: "/api/agents/\(enc)/health-check",
            body: [String: Any](),
            config: config
        )
        if let dict = raw as? [String: Any] {
            let ok = (dict["healthy"] as? Bool) ?? (dict["ok"] as? Bool) ?? (dict["available"] as? Bool) ?? false
            let msg = (dict["message"] as? String) ?? (dict["version"] as? String) ?? (ok ? "Healthy" : "Unavailable")
            return ok ? "OK · \(msg)" : msg
        }
        return "Checked"
    }

    // MARK: - Model Providers

    func fetchProviders(config: AionServerConfig) async throws -> [AionProvider] {
        let raw = try await requestJSONPublic(method: "GET", path: "/api/providers", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any] {
            items = (dict["providers"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let name = (item["name"] as? String) ?? id
            let platform = (item["platform"] as? String) ?? "openai"
            let baseURL = (item["baseUrl"] as? String) ?? (item["base_url"] as? String) ?? ""
            let models: [String]
            if let arr = item["model"] as? [String] {
                models = arr
            } else if let arr = item["models"] as? [String] {
                models = arr
            } else {
                models = []
            }
            let apiKeyStr = (item["apiKey"] as? String) ?? (item["api_key"] as? String) ?? ""
            return AionProvider(
                id: id,
                name: name,
                platform: platform,
                baseURL: baseURL,
                models: models,
                hasAPIKey: !apiKeyStr.isEmpty
            )
        }
    }

    // MARK: - MCP Servers

    func fetchMCPServers(config: AionServerConfig) async throws -> [AionMCPServer] {
        let raw = try await requestJSONPublic(method: "GET", path: "/api/mcp/servers", config: config)
        let items: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            items = arr
        } else if let dict = raw as? [String: Any] {
            items = (dict["servers"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let name = (item["name"] as? String) ?? id
            let transport = item["transport"] as? [String: Any]
            let type = (transport?["type"] as? String) ?? (item["type"] as? String) ?? "stdio"
            let target = (transport?["url"] as? String)
                ?? (transport?["command"] as? String)
                ?? (item["url"] as? String)
                ?? (item["command"] as? String)
                ?? ""
            let enabled = (item["enabled"] as? Bool) ?? true
            let status = (item["status"] as? String) ?? (enabled ? "enabled" : "disabled")
            return AionMCPServer(id: id, name: name, transportType: type, endpointOrCommand: target, enabled: enabled, status: status)
        }
    }

    func toggleMCPServer(id: String, config: AionServerConfig) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestJSONPublic(method: "POST", path: "/api/mcp/servers/\(enc)/toggle", body: [String: Any](), config: config)
    }

    func deleteMCPServer(id: String, config: AionServerConfig) async throws {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await requestJSONPublic(method: "DELETE", path: "/api/mcp/servers/\(enc)", config: config)
    }

    // MARK: - Skills Inspection & Rescan

    func readSkillDetail(skillName: String, config: AionServerConfig) async throws -> String {
        let raw = try await requestJSONPublic(
            method: "POST",
            path: "/api/skills/info",
            body: ["name": skillName, "skill_name": skillName],
            config: config
        )
        if let str = raw as? String { return str }
        if let dict = raw as? [String: Any] {
            return (dict["content"] as? String) ?? (dict["body"] as? String) ?? (dict["description"] as? String) ?? ""
        }
        return ""
    }

    func rescanSkills(config: AionServerConfig) async throws {
        _ = try await requestJSONPublic(method: "POST", path: "/api/skills/scan", body: [String: Any](), config: config)
    }

    // MARK: - General Server Settings & System Info

    func fetchRemoteSettings(config: AionServerConfig) async throws -> AionRemoteSettings {
        let raw = try await requestJSONPublic(method: "GET", path: "/api/settings", config: config)
        var settings = AionRemoteSettings()
        if let dict = raw as? [String: Any] {
            if let lang = dict["language"] as? String { settings.language = lang }
            if let v = dict["notification_enabled"] as? Bool { settings.notificationEnabled = v }
            if let v = dict["cron_notification_enabled"] as? Bool { settings.cronNotificationEnabled = v }
            if let v = dict["command_queue_enabled"] as? Bool { settings.commandQueueEnabled = v }
            if let v = dict["save_upload_to_workspace"] as? Bool { settings.saveUploadToWorkspace = v }
        }
        return settings
    }

    func patchRemoteSettings(_ settings: AionRemoteSettings, config: AionServerConfig) async throws {
        let body: [String: Any] = [
            "language": settings.language,
            "notification_enabled": settings.notificationEnabled,
            "cron_notification_enabled": settings.cronNotificationEnabled,
            "command_queue_enabled": settings.commandQueueEnabled,
            "save_upload_to_workspace": settings.saveUploadToWorkspace
        ]
        _ = try await requestJSONPublic(method: "PATCH", path: "/api/settings", body: body, config: config)
    }

    func fetchSystemInfo(config: AionServerConfig) async throws -> AionSystemInfo {
        let raw = try await requestJSONPublic(method: "GET", path: "/api/system/info", config: config)
        var info = AionSystemInfo()
        if let dict = raw as? [String: Any] {
            info.version = (dict["version"] as? String) ?? (dict["appVersion"] as? String) ?? ""
            info.platform = (dict["platform"] as? String) ?? (dict["os"] as? String) ?? ""
            info.arch = (dict["arch"] as? String) ?? ""
            info.hostname = (dict["hostname"] as? String) ?? ""
        }
        return info
    }
}
