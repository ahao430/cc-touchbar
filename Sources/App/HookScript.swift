import Foundation

@MainActor
enum HookScript {

    static let dispatcherSource = """
#!/bin/bash
# cc-touchbar dispatcher — 由 cc-touchbar.app 自动生成
# 用途：CC hook 入口，把 hook 事件追加到 jsonl 文件供 App 读取
# 不要手动编辑；如需卸载，从 ~/.claude/settings.json 删除引用即可
set -e
EVENT="${1:-Unknown}"
TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
OUT="$HOME/.claude/cc-touchbar-events.jsonl"
mkdir -p "$(dirname "$OUT")"
/usr/bin/python3 -c '
import sys, json, os
event = sys.argv[1]
ts = sys.argv[2]
try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}
out = {
    "ts": ts,
    "event": event,
    "session_id": payload.get("session_id", "") or "",
    "cwd": payload.get("cwd", "") or "",
    "transcript_path": payload.get("transcript_path", "") or "",
    "prompt": payload.get("prompt", "") or "",
    "tool_name": payload.get("tool_name", "") or "",
    "term_program": os.environ.get("TERM_PROGRAM", "") or "",
    "term_session_id": os.environ.get("TERM_SESSION_ID", "") or "",
    "tmux_pane": os.environ.get("TMUX_PANE", "") or "",
    "ppid": os.getppid(),
}
print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
' "$EVENT" "$TS" >> "$OUT"
"""

    /// dispatcher 路径（与运行时 PreferenceStore 解耦的纯函数版本）
    static var dispatcherPath: String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/cc-touchbar-dispatcher.sh").path
    }

    /// 把 dispatcher 写到 ~/.claude/cc-touchbar-dispatcher.sh 并 chmod +x
    static func install() throws -> URL {
        let url = URL(fileURLWithPath: dispatcherPath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try dispatcherSource.data(using: .utf8)?.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: dispatcherPath)
    }
}

