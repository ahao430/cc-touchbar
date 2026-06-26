import Foundation

struct ResolvedSource {
    let source: ActiveSource
    let providerName: String
    let defaultModel: String
}

enum SourceResolver {

    /// 按 L3 → L2 → L1 优先级解析当前数据源
    static func resolve(settings: ParsedSettings,
                        ccSwitchDBPresent: Bool,
                        ccSwitchActiveName: String? = nil) -> ResolvedSource {
        let baseURL = settings.env?.anthropicBaseURL ?? ""
        let isThirdParty = !baseURL.isEmpty && !isOfficial(baseURL)
        let model = pickModel(settings: settings)

        // 优先 L3
        if ccSwitchDBPresent {
            let name = ccSwitchActiveName?.isEmpty == false
                ? ccSwitchActiveName!
                : "cc switch (loading...)"
            return ResolvedSource(
                source: .ccSwitch,
                providerName: name,
                defaultModel: model
            )
        }

        // 其次 L2
        if isThirdParty {
            return ResolvedSource(
                source: .envVars(baseURL: baseURL),
                providerName: friendlyName(for: baseURL),
                defaultModel: model
            )
        }

        // 默认 L1
        return ResolvedSource(
            source: .official,
            providerName: "Claude Official",
            defaultModel: model.isEmpty ? "claude-sonnet-4-5" : model
        )
    }

    private static func pickModel(settings: ParsedSettings) -> String {
        if let m = settings.env?.anthropicModel, !m.isEmpty { return m }
        if let m = settings.env?.sonnetModel, !m.isEmpty { return m }
        if let m = settings.env?.opusModel, !m.isEmpty { return m }
        if let m = settings.env?.haikuModel, !m.isEmpty { return m }
        return ""
    }

    private static func isOfficial(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("anthropic.com") || lowered.contains("claude.ai")
    }

    /// L2 下从 BASE_URL hostname 推断 provider 友好名
    static func friendlyName(for baseURL: String) -> String {
        guard let host = URL(string: baseURL)?.host else { return baseURL }
        return providerNameByHost[host] ?? host
    }

    static let providerNameByHost: [String: String] = [
        "open.bigmodel.cn":       "Zhipu GLM",
        "api.deepseek.com":       "DeepSeek",
        "api.moonshot.cn":        "Moonshot Kimi",
        "dashscope.aliyuncs.com": "阿里通义",
        "api.mistral.ai":         "Mistral",
        "api.openai.com":         "OpenAI",
        "api.anthropic.com":      "Claude Official",
        "generativelanguage.googleapis.com": "Google Gemini",
    ]
}
