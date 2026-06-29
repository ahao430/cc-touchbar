import Foundation

/// cc switch SQLite 只读桥接（v3 范围，先做最小读取）
@MainActor
final class CCSwitchBridge {

    struct Provider: Equatable {
        let id: String
        let name: String
        let baseURL: String?
        let isActive: Bool
        let meta: String
    }

    private(set) var activeProvider: Provider?
    private(set) var allProviders: [Provider] = []
    private(set) var balanceText: String = "余额 —"

    /// 只关心 Claude Code 这条线；cc-switch 的 providers 表会同时持有
    /// claude/codex/gemini/opencode 等多种 app_type，各自独立标记 is_current。
    private let appType = "claude"

    var onReload: (() -> Void)?

    var dbURL: URL? { AppPathsResolver.locateCCSwitchDB() }

    var isAvailable: Bool { dbURL != nil }

    /// 读取（SQlite 简易实现：直接 sqlite3 C API）
    func reload() {
        guard let url = dbURL else { return }
        // 用 /usr/bin/sqlite3 命令行避免引入 C 库链接问题
        Task { [weak self] in
            await self?.readViaCLI(url: url)
            await MainActor.run { self?.onReload?() }
        }
    }

    // MARK: - 实现细节

    private func readViaCLI(url: URL) async {
        // providers(id, app_type, name, settings_config, is_current, meta, ...)
        // PRIMARY KEY (id, app_type)
        let providersSQL = """
            SELECT id, name, settings_config, is_current, meta
            FROM providers
            WHERE app_type = '\(appType)';
            """
        let providersOut = try? ShellRunner.runCapture(
            command: "/usr/bin/sqlite3",
            arguments: ["-json", "-readonly", url.path, providersSQL],
            timeout: 5
        )

        var providers: [Provider] = []
        var active: Provider?
        if let out = providersOut,
           let data = out.data(using: .utf8),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for row in rows {
                let id = (row["id"] as? String) ?? ""
                let name = (row["name"] as? String) ?? id
                let activeInt = (row["is_current"] as? Int) ?? 0
                let settingsConfig = (row["settings_config"] as? String) ?? ""
                let baseURL = extractBaseURL(from: settingsConfig)
                let meta = (row["meta"] as? String) ?? "{}"
                let p = Provider(id: id, name: name, baseURL: baseURL,
                                 isActive: activeInt != 0, meta: meta)
                providers.append(p)
                if p.isActive { active = p }
            }
        }

        self.allProviders = providers
        self.activeProvider = active
        self.balanceText = await queryBalance(for: active)
    }

    private func queryBalance(for provider: Provider?) async -> String {
        guard let provider,
              let meta = parseJSON(provider.meta),
              let script = meta["usage_script"] as? [String: Any],
              (script["enabled"] as? Bool) == true else { return "余额 —" }

        switch script["templateType"] as? String {
        case "newapi":
            return await queryNewAPIBalance(from: script) ?? "余额 —"
        case "token_plan":
            return await queryTokenPlan(from: script, provider: provider) ?? "余额 —"
        case "balance":
            return await queryOfficialBalance(from: script, provider: provider) ?? "余额 —"
        default:
            return await queryNewAPIBalance(from: script) ?? "余额 —"
        }
    }

    private func queryNewAPIBalance(from script: [String: Any]) async -> String? {
        guard let baseURL = script["baseUrl"] as? String,
              let accessToken = script["accessToken"] as? String,
              let userID = script["userId"] as? String,
              let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/user/self") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("cc-switch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(userID, forHTTPHeaderField: "New-Api-User")
        request.timeoutInterval = 12

        guard let json = await fetchJSON(request),
              (json["success"] as? Bool) == true,
              let payload = json["data"] as? [String: Any],
              let quota = parseDouble(payload["quota"]) else {
            return nil
        }

        let unit = (script["code"] as? String)?.contains("unit: \"CNY\"") == true ? "CNY" : "USD"
        return formatBalance(quota / 500000, unit: unit)
    }

    private func queryTokenPlan(from script: [String: Any], provider: Provider) async -> String? {
        guard let apiKey = apiKey(from: script, provider: provider) else { return nil }
        switch script["codingPlanProvider"] as? String {
        case "zhipu":
            return await queryZhipuTokenPlan(apiKey: apiKey)
        default:
            return nil
        }
    }

    private func queryZhipuTokenPlan(apiKey: String) async -> String? {
        for base in ["https://open.bigmodel.cn", "https://api.z.ai"] {
            guard let url = URL(string: base + "/api/monitor/usage/quota/limit") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = 12

            guard let json = await fetchJSON(request),
                  (json["success"] as? Bool) == true,
                  let data = json["data"] as? [String: Any],
                  let limits = data["limits"] as? [[String: Any]] else { continue }
            let tokenLimits = limits.filter { ($0["type"] as? String) == "TOKENS_LIMIT" }
            let fiveHour = tokenLimits.first { parseInt($0["unit"]) == 3 } ?? tokenLimits.first
            guard let item = fiveHour,
                  let rawPercent = parseDouble(item["percentage"]) else { continue }
            let mode = await PreferenceStore.shared.subscriptionPercentMode
            let displayPercent = mode == .remaining ? (100 - rawPercent) : rawPercent
            var text = "5h \(formatPercent(displayPercent))%"
            if let resetMs = parseDouble(item["nextResetTime"]) {
                let remaining = resetMs / 1000 - Date().timeIntervalSince1970
                if remaining > 0 {
                    text += " ·\(formatHMS(remaining))"
                }
            }
            return text
        }
        return nil
    }

    private func queryOfficialBalance(from script: [String: Any], provider: Provider) async -> String? {
        guard let apiKey = apiKey(from: script, provider: provider) else { return nil }
        let name = provider.name.lowercased()
        if name.contains("deepseek") {
            return await queryDeepSeekBalance(apiKey: apiKey)
        }
        return nil
    }

    private func queryDeepSeekBalance(apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        guard let json = await fetchJSON(request),
              (json["is_available"] as? Bool) == true,
              let infos = json["balance_infos"] as? [[String: Any]],
              let first = infos.first,
              let value = parseDouble(first["total_balance"]) else { return nil }
        let unit = (first["currency"] as? String) ?? ""
        return formatBalance(value, unit: unit)
    }

    private func formatBalance(_ value: Double, unit: String) -> String {
        let formatted: String
        if value >= 1000 {
            formatted = String(format: "%.0f", value)
        } else if value >= 100 {
            formatted = String(format: "%.1f", value)
        } else {
            formatted = String(format: "%.2f", value)
        }
        return unit.isEmpty ? "余额 \(formatted)" : "余额 \(formatted) \(unit)"
    }

    private func formatPercent(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func formatHMS(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s >= 3600 { return "\(s/3600)h\(s/60%60)m" }
        if s >= 60 { return "\(s/60)m\(s%60)s" }
        return "\(s)s"
    }

    private func fetchJSON(_ request: URLRequest) async -> [String: Any]? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func apiKey(from script: [String: Any], provider: Provider) -> String? {
        if let apiKey = script["apiKey"] as? String, !apiKey.isEmpty { return apiKey }
        guard let settings = providerSettings(for: provider),
              let env = settings["env"] as? [String: Any] else { return nil }
        return env["ANTHROPIC_AUTH_TOKEN"] as? String
    }

    private func providerSettings(for provider: Provider) -> [String: Any]? {
        guard let url = dbURL else { return nil }
        let sql = """
            SELECT settings_config
            FROM providers
            WHERE app_type = '\(appType)' AND id = '\(provider.id.replacingOccurrences(of: "'", with: "''"))'
            LIMIT 1;
            """
        guard let out = try? ShellRunner.runCapture(
            command: "/usr/bin/sqlite3",
            arguments: ["-json", "-readonly", url.path, sql],
            timeout: 5
        ),
              let data = out.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let config = rows.first?["settings_config"] as? String else { return nil }
        return parseJSON(config)
    }

    private func parseInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private func parseDouble(_ v: Any?) -> Double? {
        if let s = v as? String, let d = Double(s) { return d }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    private func extractBaseURL(from settingsConfig: String) -> String? {
        guard !settingsConfig.isEmpty,
              let data = settingsConfig.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let env = obj["env"] as? [String: String] {
            return env["ANTHROPIC_BASE_URL"]
        }
        return nil
    }
}
