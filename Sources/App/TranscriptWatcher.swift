import Foundation
import Observation

@MainActor
final class TranscriptWatcher {

    private weak var store: SessionStore?
    private weak var state: AppState?
    private var timer: Timer?
    private var lastSize: Int64 = -1

    func attach(to store: SessionStore, state: AppState) {
        self.store = store
        self.state = state
        observeFocus()
        detectGitBranch()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.detectGitBranch()
            }
        }
    }

    private func observeFocus() {
        guard let store else { return }
        Observation.withObservationTracking {
            _ = store.focusedSessionID
            _ = store.focusedSession
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.detectGitBranch()
                self?.observeFocus()
            }
        }
    }

    private func detectGitBranch() {
        guard let state else { return }
        guard let cwd = store?.focusedSession?.cwd.path else {
            state.gitBranch = nil
            return
        }
        let currentURL = URL(fileURLWithPath: cwd)
        let gitCwd = nearestGitDirectory(from: currentURL) ?? currentURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", gitCwd.path, "branch", "--show-current"]
        task.qualityOfService = .utility
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let branch = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            state.gitBranch = (branch?.isEmpty == false) ? branch : nil
        } catch {
            state.gitBranch = nil
        }
    }

    private func nearestGitDirectory(from url: URL) -> URL? {
        var current = url
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private func refresh() {
        guard let store, let state else { return }

        guard let path = store.focusedSession?.transcriptPath,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            clear()
            return
        }

        let url = URL(fileURLWithPath: path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        if size == lastSize { return }
        lastSize = size

        guard size > 0,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            clear()
            return
        }

        var lastUsage: Usage?
        var lastModel: String?
        var billedTotal: Double = 0
        var assistantCount = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any] else {
                continue
            }
            if let m = message["model"] as? String, !m.isEmpty {
                lastModel = m
            }
            guard let usage = message["usage"] as? [String: Any] else {
                continue
            }
            let u = Usage(
                input: (usage["input_tokens"] as? Int) ?? 0,
                cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0,
                cacheCreation: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                output: (usage["output_tokens"] as? Int) ?? 0
            )
            lastUsage = u
            billedTotal += Double(u.input)
                      + Double(u.cacheCreation) * 1.25
                      + Double(u.cacheRead) * 0.1
                      + Double(u.output)
            assistantCount += 1
        }

        if let m = lastModel {
            state.contextModelName = m
        }

        guard let u = lastUsage else {
            state.contextUsedTokens = nil
            state.contextLimitTokens = nil
            state.sessionBilledTokens = nil
            state.sessionAssistantTurns = nil
            state.cacheHitRate = nil
            return
        }

        state.contextUsedTokens = u.input + u.cacheRead + u.cacheCreation
        state.contextLimitTokens = Self.contextLimit(for: lastModel ?? state.defaultModel)
        state.sessionBilledTokens = Int(billedTotal.rounded())
        state.sessionAssistantTurns = assistantCount

        let totalInput = u.input + u.cacheRead + u.cacheCreation
        state.cacheHitRate = totalInput > 0 ? Double(u.cacheRead) / Double(totalInput) : 0
    }

    private func clear() {
        lastSize = -1
        state?.contextUsedTokens = nil
        state?.contextLimitTokens = nil
        state?.contextModelName = nil
        state?.sessionBilledTokens = nil
        state?.sessionAssistantTurns = nil
        state?.cacheHitRate = nil
        state?.gitBranch = nil
    }

    private struct Usage {
        let input: Int
        let cacheRead: Int
        let cacheCreation: Int
        let output: Int
    }

    private static func contextLimit(for model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("1m") { return 1_000_000 }
        if lower.contains("gemini-2.5-pro") { return 2_000_000 }
        if lower.contains("gemini") { return 1_000_000 }
        return 200_000
    }
}
