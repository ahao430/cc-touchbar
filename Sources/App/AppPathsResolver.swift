import Foundation

@MainActor
enum AppPathsResolver {

    struct AppPathsFile: Codable {
        let appConfigDirOverride: String?

        enum CodingKeys: String, CodingKey {
            case appConfigDirOverride = "app_config_dir_override"
        }
    }

    /// cc switch db 来源标签（诊断面板用）
    enum CCSwitchDBSource: String {
        case manual = "手动"
        case ccswitchOverride = "cc switch override"
        case defaultPath = "默认"
        case missing = "未找到"
    }

    static func locateCCSwitchDB() -> URL? { resolvedCCSwitchDB().url }

    static func resolvedCCSwitchDB() -> (url: URL?, source: CCSwitchDBSource) {
        // 1. cc-touchbar 自己的手动覆盖（最高优先级）
        if let manual = PreferenceStore.shared.ccSwitchDBOverride {
            let url = URL(fileURLWithPath: manual)
            if FileManager.default.fileExists(atPath: url.path) {
                return (url, .manual)
            }
        }
        // 2. cc switch 自己写出的 app_paths.json override
        if let override = readCCSwitchOverride() {
            let url = URL(fileURLWithPath: override).appendingPathComponent("cc-switch.db")
            if FileManager.default.fileExists(atPath: url.path) {
                return (url, .ccswitchOverride)
            }
        }
        // 3. 默认路径
        let defaultDB = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cc-switch/cc-switch.db")
        if FileManager.default.fileExists(atPath: defaultDB.path) {
            return (defaultDB, .defaultPath)
        }
        return (nil, .missing)
    }

    private static func readCCSwitchOverride() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.ccswitch.desktop/app_paths.json")
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(AppPathsFile.self, from: data)
        else { return nil }
        return parsed.appConfigDirOverride
    }
}
