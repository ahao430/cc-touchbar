import Foundation

struct Session: Identifiable, Equatable {
    let id: String
    var cwd: URL
    var hostApp: String
    var pid: pid_t?
    var termSessionId: String?
    var tmuxPane: String?
    var startedAt: Date
    var lastEventAt: Date
    var lastEventType: String
    var status: Status
    var transcriptPath: String?

    enum Status: String, Equatable {
        case idle
        case thinking
        case streaming
        case stopped

        var label: String {
            switch self {
            case .idle: return "idle"
            case .thinking: return "thinking"
            case .streaming: return "streaming"
            case .stopped: return "stopped"
            }
        }
    }

    var displayCwd: String {
        let path = cwd.path
        if path == NSHomeDirectory() { return "~" }
        if path.hasPrefix(NSHomeDirectory() + "/") {
            return "~" + path.dropFirst(NSHomeDirectory().count)
        }
        return path
    }

    var projectName: String {
        cwd.lastPathComponent
    }

    var duration: TimeInterval {
        max(0, Date().timeIntervalSince(startedAt))
    }
}

struct HookEvent: Decodable, Equatable {
    let ts: String
    let event: String
    let session_id: String?
    let cwd: String?
    let transcript_path: String?
    let term_program: String?
    let term_session_id: String?
    let tmux_pane: String?
    let ppid: pid_t?
}
