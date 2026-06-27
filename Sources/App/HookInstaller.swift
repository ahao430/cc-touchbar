import Foundation

enum HookInstaller {

    struct InstallResult {
        var dispatcherInstalled: Bool
        var settingsMerged: Bool
        var backupURL: URL?
        var registeredEvents: [String]
        var error: String?
    }

    /// CC hook 事件清单，按重要度排序
    static let eventsToRegister = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",
        "SessionEnd"
    ]

    /// 完整安装：dispatcher + 合并 settings.json
    @MainActor
    static func install() -> InstallResult {
        var result = InstallResult(
            dispatcherInstalled: false,
            settingsMerged: false,
            backupURL: nil,
            registeredEvents: [],
            error: nil
        )

        // 1. dispatcher
        do {
            let url = try HookScript.install()
            PreferenceStore.shared.dispatcherPath = url.path
            result.dispatcherInstalled = true
        } catch {
            result.error = "dispatcher 安装失败: \(error.localizedDescription)"
            return result
        }

        // 2. settings.json 合并
        let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
        do {
            // 备份
            let backupURL = settingsURL.appendingPathExtension("bak.cc-touchbar")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.removeItem(at: backupURL)
                }
                try FileManager.default.copyItem(at: settingsURL, to: backupURL)
                result.backupURL = backupURL
            }

            let root = readOrCreateJSON(at: settingsURL)
            let merged = mergeHooks(into: root, dispatcherPath: PreferenceStore.shared.dispatcherURL.path)
            try writeJSON(root: merged, to: settingsURL)
            result.settingsMerged = true
            result.registeredEvents = eventsToRegister
            PreferenceStore.shared.hooksInstalled = true
        } catch {
            result.error = "settings.json 合并失败: \(error.localizedDescription)"
        }

        return result
    }

    /// 卸载：从 settings.json 移除引用（dispatcher 文件保留）
    @MainActor
    static func uninstall() -> InstallResult {
        var result = InstallResult(
            dispatcherInstalled: HookScript.isInstalled,
            settingsMerged: false,
            backupURL: nil,
            registeredEvents: [],
            error: nil
        )

        let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
        do {
            let root = readOrCreateJSON(at: settingsURL)
            let cleaned = removeOurHooks(from: root)
            try writeJSON(root: cleaned, to: settingsURL)
            result.settingsMerged = true
            PreferenceStore.shared.hooksInstalled = false
        } catch {
            result.error = "卸载失败: \(error.localizedDescription)"
        }
        return result
    }

    /// 检测 settings.json 里是否已注册了我们的 dispatcher
    static func isRegisteredInSettings() -> Bool {
        let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
        guard let root = try? readOrCreateJSON(at: settingsURL) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let inner = group["hooks"] as? [[String: Any]] else { continue }
                for h in inner {
                    if let cmd = h["command"] as? String,
                       cmd.contains("cc-touchbar-dispatcher.sh") {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - internal

    private static func readOrCreateJSON(at url: URL) -> [String: Any] {
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return [:]
    }

    private static func mergeHooks(into root: [String: Any], dispatcherPath: String) -> [String: Any] {
        var root = root
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        for event in eventsToRegister {
            var arr = (hooks[event] as? [[String: Any]]) ?? []
            // 已存在则跳过
            let already = arr.contains { group in
                guard let inner = group["hooks"] as? [[String: Any]] else { return false }
                return inner.contains { ($0["command"] as? String)?.contains("cc-touchbar-dispatcher.sh") == true }
            }
            if already { continue }

            arr.append([
                "matcher": "",
                "hooks": [[
                    "type": "command",
                    "command": "\(dispatcherPath) \(event)"
                ]]
            ])
            hooks[event] = arr
        }

        root["hooks"] = hooks
        return root
    }

    private static func removeOurHooks(from root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let filtered = groups.compactMap { group -> [String: Any]? in
                guard var inner = group["hooks"] as? [[String: Any]] else { return group }
                inner.removeAll { ($0["command"] as? String)?.contains("cc-touchbar-dispatcher.sh") == true }
                if inner.isEmpty { return nil }
                var g = group
                g["hooks"] = inner
                return g
            }
            if filtered.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filtered
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return root
    }

    private static func writeJSON(root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [
            .prettyPrinted,
            .sortedKeys
        ])
        try data.write(to: url, options: .atomic)
    }
}
