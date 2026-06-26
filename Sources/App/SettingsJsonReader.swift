import Foundation

struct ClaudeSettings: Codable {
    let env: [String: String]?
    let permissions: [String: AnyCodable]?
}

struct ParsedSettings {
    let env: EnvBlock?
    struct EnvBlock {
        let anthropicBaseURL: String?
        let anthropicModel: String?
        let haikuModel: String?
        let sonnetModel: String?
        let opusModel: String?
    }
}

enum SettingsJsonReader {

    static func read(at configDir: URL) throws -> ParsedSettings {
        let url = configDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ParsedSettings {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedSettings(env: nil)
        }
        guard let envDict = root["env"] as? [String: String] else {
            return ParsedSettings(env: nil)
        }

        return ParsedSettings(env: .init(
            anthropicBaseURL: envDict["ANTHROPIC_BASE_URL"],
            anthropicModel: envDict["ANTHROPIC_MODEL"],
            haikuModel: envDict["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] ?? envDict["ANTHROPIC_DEFAULT_HAIKU_MODEL"],
            sonnetModel: envDict["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] ?? envDict["ANTHROPIC_DEFAULT_SONNET_MODEL"],
            opusModel: envDict["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"] ?? envDict["ANTHROPIC_DEFAULT_OPUS_MODEL"]
        ))
    }
}

/// 用于解码任意 JSON 值的辅助类型
struct AnyCodable: Codable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String:  try container.encode(v)
        case let v as Int:     try container.encode(v)
        case let v as Bool:    try container.encode(v)
        default: try container.encodeNil()
        }
    }
}
