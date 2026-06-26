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
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
                self?.observeFocus()
            }
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
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }
            let u = Usage(
                input: (usage["input_tokens"] as? Int) ?? 0,
                cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0,
                cacheCreation: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                output: (usage["output_tokens"] as? Int) ?? 0
            )
            lastUsage = u
            lastModel = message["model"] as? String
            billedTotal += Double(u.input)
                      + Double(u.cacheCreation) * 1.25
                      + Double(u.cacheRead) * 0.1
                      + Double(u.output)
            assistantCount += 1
        }

        guard let u = lastUsage else {
            clear()
            return
        }

        state.contextUsedTokens = u.input + u.cacheRead + u.cacheCreation
        state.contextModelName = lastModel
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
