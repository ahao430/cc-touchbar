import Foundation

@MainActor
enum ClaudeDetector {

    enum Source: String {
        case manual = "手动"
        case which = "PATH"
        case nvm = "nvm fallback"
        case missing = "未找到"
    }

    /// 解析 claude binary 路径
    /// 优先级：手动覆盖 → `which claude`（登录 shell）→ 扫 nvm versions 取最新
    static func locateBinary(timeout: TimeInterval = 3) throws -> String {
        if let (path, _) = resolvedBinary(timeout: timeout) as? (String, Source) { return path }
        throw ClaudeDetectError.notFound
    }

    static func resolvedBinary(timeout: TimeInterval = 3) -> (path: String?, source: Source) {
        // 1. 手动覆盖
        if let manual = PreferenceStore.shared.claudeBinOverride,
           FileManager.default.isExecutableFile(atPath: manual) {
            return (manual, .manual)
        }
        // 2. which claude（登录 shell）
        if let path = try? whichClaude(timeout: timeout),
           FileManager.default.isExecutableFile(atPath: path) {
            return (path, .which)
        }
        // 3. nvm fallback
        if let fallback = scanNvmFallback() {
            return (fallback, .nvm)
        }
        return (nil, .missing)
    }

    private static func whichClaude(timeout: TimeInterval) throws -> String? {
        let result = try ShellRunner.run(command: "which claude", timeout: timeout)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func scanNvmFallback() -> String? {
        let nvmDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".nvm/versions/node")
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: nvmDir,
            includingPropertiesForKeys: nil
        ) else { return nil }

        return candidates
            .filter { $0.lastPathComponent.hasPrefix("v") }
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .map { $0.appendingPathComponent("bin/claude") }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })?
            .path
    }
}

enum ClaudeDetectError: Error, CustomStringConvertible {
    case notFound

    var description: String {
        switch self {
        case .notFound: return "claude command not found in PATH or nvm"
        }
    }
}
