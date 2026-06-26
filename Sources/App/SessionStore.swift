import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class SessionStore {

    var sessions: [String: Session] = [:]

    /// 触发 1：当前 frontmost 的 NSWorkspace app（PID）
    var focusedAppPID: pid_t?

    /// 触发 2：最近触发 hook 的 session_id（优先级高于 T1）
    var lastHookActiveSessionID: String?

    /// 综合解析的焦点 session
    var focusedSessionID: String? {
        if let id = lastHookActiveSessionID,
           let s = sessions[id],
           Date().timeIntervalSince(s.lastEventAt) < 8 {
            return id
        }
        // T1：按 PID 反查 session
        if let pid = focusedAppPID {
            for (_, s) in sessions where s.pid == pid {
                return s.id
            }
        }
        // 兜底：返回最近活跃的 session
        return sessions.values
            .sorted { $0.lastEventAt > $1.lastEventAt }
            .first?.id
    }

    var focusedSession: Session? {
        guard let id = focusedSessionID else { return nil }
        return sessions[id]
    }

    var activeSessions: [Session] {
        sessions.values
            .filter { Date().timeIntervalSince($0.lastEventAt) < 3600 } // 1h 内活跃
            .sorted { $0.lastEventAt > $1.lastEventAt }
    }

    var totalSessions: Int { sessions.count }

    func apply(event: HookEvent) {
        guard let sid = event.session_id, !sid.isEmpty else { return }
        let now = Date()
        var s = sessions[sid] ?? Session(
            id: sid,
            cwd: URL(fileURLWithPath: event.cwd ?? NSHomeDirectory()),
            hostApp: event.term_program ?? "unknown",
            pid: event.ppid,
            termSessionId: event.term_session_id,
            tmuxPane: event.tmux_pane,
            startedAt: parseISO(event.ts) ?? now,
            lastEventAt: now,
            lastEventType: event.event,
            status: .idle,
            transcriptPath: event.transcript_path
        )

        s.lastEventAt = now
        s.lastEventType = event.event
        if let cwd = event.cwd, !cwd.isEmpty {
            s.cwd = URL(fileURLWithPath: cwd)
        }
        if let tp = event.term_program, !tp.isEmpty { s.hostApp = tp }
        if let ts = event.term_session_id, !ts.isEmpty { s.termSessionId = ts }
        if let tp = event.tmux_pane, !tp.isEmpty { s.tmuxPane = tp }
        if let pid = event.ppid { s.pid = pid }
        if let tp = event.transcript_path, !tp.isEmpty { s.transcriptPath = tp }

        s.status = statusFor(event: event.event)

        sessions[sid] = s
        lastHookActiveSessionID = sid

        // 清理 24h 没动的 session
        purgeStale()
    }

    func setFocusedApp(pid: pid_t?) {
        focusedAppPID = pid
    }

    func remove(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }

    // MARK: -

    private func statusFor(event: String) -> Session.Status {
        switch event {
        case "SessionStart": return .idle
        case "UserPromptSubmit": return .thinking
        case "PreToolUse": return .thinking
        case "PostToolUse": return .streaming
        case "MessageDisplay": return .streaming
        case "Stop", "SubagentStop": return .idle
        case "SessionEnd": return .stopped
        default: return .idle
        }
    }

    private func purgeStale() {
        let cutoff = Date().addingTimeInterval(-86400) // 24h
        for (id, s) in sessions {
            if s.lastEventAt < cutoff {
                sessions.removeValue(forKey: id)
            }
        }
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
