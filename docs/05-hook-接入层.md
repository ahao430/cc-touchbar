# 05 - hook 接入层

> Claude Code hooks 触发时，hook 脚本把事件写入 `~/.claude/cc-touchbar-events.jsonl`，App 用 FSEvents 监听这个文件并解析。
>
> **没有这条通道，App 就只能看 cc switch 的状态，看不到 Claude Code 的实际活动。** 这是实现"实时 session 状态"的关键。
>
> **所有三个数据源层级都需要 hook 接入**（L1/L2/L3 都依赖它拿 session 状态）。

## 完整 hook 事件列表

agent 从 Claude Code 官方文档确认的事件：

`SessionStart`、`Setup`、`InstructionsLoaded`、`UserPromptSubmit`、`UserPromptExpansion`、`MessageDisplay`、`PreToolUse`、`PermissionRequest`、`PermissionDenied`、`PostToolUse`、`PostToolUseFailure`、`PostToolBatch`、`Notification`、`SubagentStart`、`SubagentStop`、`TaskCreated`、`TaskCompleted`、`Stop`、`StopFailure`、`TeammateIdle`、`ConfigChange`、`CwdChanged`、`FileChanged`、`WorktreeCreate`、`WorktreeRemove`、`PreCompact`、`PostCompact`、`Elicitation`、`ElicitationResult`、`SessionEnd`

### App 关心的事件（最小集）

| 事件 | 用途 | 状态映射 |
|---|---|---|
| `SessionStart` | 注册新 session（含 cwd / hostApp / TTY） | 新建 Session |
| `UserPromptSubmit` | 用户开始输入 | `status = .thinking` |
| `PreToolUse` | 模型决定用工具 | `status = .thinking` |
| `MessageDisplay` | 模型在输出 tokens（流式） | `status = .streaming` |
| `Stop` | 一轮对话结束 | `status = .idle` |
| `StopFailure` | 一轮对话异常终止 | `status = .error` |
| `Notification` | UI 事件（permission_prompt / idle_prompt） | 标记 session 等待用户操作 |
| `CwdChanged` | 用户在 CC 里 cd 了 | 更新 `session.cwd` |
| `ConfigChange` | 用户改了 CC 配置 | 触发 modelMapping 重新读取 |
| `SessionEnd` | CC 进程退出 | 标记 `endedAt`，TTL 后清理 |

> MessageDisplay 是流式 token 的最佳信号，**不是** Notification。Notification 只在 UI 事件（permission_prompt、idle_prompt、auth_success、elicitation_*）触发。

### L1（官方订阅）下额外利用

- `PostToolUse` + `PostToolBatch`：累计 token 用量，自算"今日请求数"等
- `Stop` / `StopFailure`：累计对话轮次

L1 没有 cc switch 的 cost 数据，但仍能用 hook 自算基础统计。

## JSONL 通道设计

### 为什么用文件而不是 HTTP/IPC？

| 方案 | 优点 | 缺点 |
|---|---|---|
| **JSONL 文件 + FSEvents** ✅ | 零依赖；和现有 Poller 模式一致；hook 失败也能事后查 | 高频写有 I/O 成本 |
| App 内置 HTTP server | 实时性好 | 需管理端口、鉴权、CORS |
| Unix socket / named pipe | 实时、低开销 | 需管理 socket 文件、生命周期 |
| 直接写 cc switch 的 db | 一处存储 | hook 进程权限/锁问题，且混淆 cc switch 自己的状态 |

**选 JSONL：** hook 脚本最简单（一个 `echo >> file`），App 端已有 FSEvents 基建（监听 `.db` 和 `settings.json` 已经在做），多一个文件零边际成本。

### Hook 脚本

`~/.claude/hooks/cc-touchbar-dispatcher.sh`：

```bash
#!/bin/bash
# Claude Code hook dispatcher for cc-touchbar
# 注册方式：在 ~/.claude/settings.json 的 hooks 块里指向这个脚本

set -euo pipefail

EVENT_FILE="$HOME/.claude/cc-touchbar-events.jsonl"
TMP=""

# 从 stdin 读 hook payload（JSON）
PAYLOAD="$(cat)"

# 提取 session_id（用于过滤无关事件）
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# 注入环境快照（OS 窗口匹配用）
ENRICHED=$(jq -c \
    --arg term_program "${TERM_PROGRAM:-}" \
    --arg term_session_id "${TERM_SESSION_ID:-}" \
    --arg tmux_pane "${TMUX_PANE:-}" \
    --arg wezterm_pane "${WEZTERM_PANE:-}" \
    --arg ghostty_res "${GHOSTTY_RESOURCES_DIR:-}" \
    --argjson ppid "$PPID" \
    --arg project_dir "${CLAUDE_PROJECT_DIR:-}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    '. + {
        _cc_touchbar: {
            ts: $ts,
            ppid: $ppid,
            term_program: $term_program,
            term_session_id: $term_session_id,
            tmux_pane: $tmux_pane,
            wezterm_pane: $wezterm_pane,
            ghostty: ($ghostty_res | length > 0),
            project_dir: $project_dir
        }
    }' <<< "$PAYLOAD")

# 原子追加（先写 tmp，再 cat >> 主文件）
TMP=$(mktemp)
echo "$ENRICHED" > "$TMP"
cat "$TMP" >> "$EVENT_FILE"
rm -f "$TMP"
```

### 注册到 Claude Code

在 `~/.claude/settings.json` 添加：

```json
{
  "hooks": {
    "SessionStart":      [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "UserPromptSubmit":  [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "PreToolUse":        [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "MessageDisplay":    [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "Stop":              [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "StopFailure":       [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "Notification":      [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "CwdChanged":        [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "ConfigChange":      [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}],
    "SessionEnd":        [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/cc-touchbar-dispatcher.sh"}]}]
  }
}
```

**Setup Wizard 负责安装这个脚本和合并 settings.json**（用户已存在的 hooks 用 jq 合并，不覆盖）。

## SessionStart payload schema

hook 脚本注入 `_cc_touchbar` 块后的完整事件：

```json
{
  "session_id": "abc-123-def-456",
  "transcript_path": "/Users/wanghao/.claude/projects/.../abc-123.jsonl",
  "cwd": "/Users/wanghao/workspace/cc-touchbar",
  "hook_event_name": "SessionStart",
  "permission_mode": "default",

  "_cc_touchbar": {
    "ts": "2026-06-26T08:30:00.123Z",
    "ppid": 45678,
    "term_program": "iTerm.app",
    "term_session_id": "w0t0p1:ABCD-1234",
    "tmux_pane": "",
    "wezterm_pane": "",
    "ghostty": false,
    "project_dir": "/Users/wanghao/workspace/cc-touchbar"
  }
}
```

字段说明：

| 字段 | 来源 | 用途 |
|---|---|---|
| `session_id` | Claude Code payload | session 唯一标识 |
| `cwd` | Claude Code payload | 项目目录 |
| `transcript_path` | Claude Code payload | 对话记录文件 |
| `_cc_touchbar.ts` | hook 脚本 | 事件时间戳 |
| `_cc_touchbar.ppid` | `$PPID` | 父进程（shell），用于进程链追踪 |
| `_cc_touchbar.term_program` | `$TERM_PROGRAM` | 宿主 app |
| `_cc_touchbar.term_session_id` | `$TERM_SESSION_ID` | iTerm/Terminal 的 tab ID |
| `_cc_touchbar.tmux_pane` | `$TMUX_PANE` | tmux pane ID |
| `_cc_touchbar.wezterm_pane` | `$WEZTERM_PANE` | WezTerm pane ID |
| `_cc_touchbar.ghostty` | `$GHOSTTY_RESOURCES_DIR` 是否非空 | 是否在 Ghostty 内 |
| `_cc_touchbar.project_dir` | `$CLAUDE_PROJECT_DIR` | 项目根 |

## App 端解析

```swift
final class HookIngester {
    let state: AppState
    private var watcher: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var lastSize: UInt64 = 0
    private var partialBuffer: Data = Data()      // 跨 FSEvent 的半行

    func start(fileURL: URL) {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forReadingFrom: fileURL)
        lastSize = fileHandle?.seekToEndOfFile() ?? 0

        let fd = open(fileURL.path, O_EVTONLY)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in self?.readNewLines() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func readNewLines() {
        guard let fh = fileHandle else { return }
        fh.seek(toFileOffset: lastSize)
        let data = fh.readDataToEndOfFile()
        lastSize = fh.offsetInFile

        partialBuffer.append(data)
        let lines = splitLines(buffer: &partialBuffer)   // 留最后未换行的

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(HookEvent.self, from: lineData) else {
                continue
            }
            DispatchQueue.main.async { [weak self] in
                self?.apply(event)
            }
        }
    }

    private func apply(_ event: HookEvent) {
        switch event.hookEventName {
        case "SessionStart":
            let s = event.ccTouchbar
            state.sessions[event.sessionID] = Session(
                id: event.sessionID,
                cwd: URL(fileURLWithPath: event.cwd),
                hostApp: s.hostApp,
                termSessionID: s.termSessionID,
                tmuxPane: s.tmuxPane,
                status: .idle,
                lastActivityAt: Date(),
                startedAt: Date()
            )
            // 建立窗口 → session 映射（详见 06-多窗口追踪.md）
            if let tabId = s.termSessionID ?? s.tmuxPane ?? s.weztermPane {
                let key = TermTabKey(hostApp: s.hostApp.rawValue, tabId: tabId)
                state.sessionByTab[key] = event.sessionID
            }
        case "UserPromptSubmit", "PreToolUse":
            state.sessions[event.sessionID]?.status = .thinking
            state.sessions[event.sessionID]?.lastActivityAt = Date()
        case "MessageDisplay":
            state.sessions[event.sessionID]?.status = .streaming
            state.sessions[event.sessionID]?.lastActivityAt = Date()
        case "Stop":
            state.sessions[event.sessionID]?.status = .idle
            state.sessions[event.sessionID]?.lastActivityAt = Date()
        case "StopFailure":
            state.sessions[event.sessionID]?.status = .error
        case "CwdChanged":
            state.sessions[event.sessionID]?.cwd = URL(fileURLWithPath: event.cwd)
        case "SessionEnd":
            state.sessions[event.sessionID]?.endedAt = Date()
        case "Notification", "ConfigChange":
            state.sessions[event.sessionID]?.lastActivityAt = Date()
        default:
            break
        }
    }
}
```

## Session 清理

避免 `state.sessions` 无限增长：

```swift
// 每 5 分钟扫一次，清理 ended 超过 1 小时或 lastActivity 超过 24 小时的
func gcSessions() {
    let cutoff1 = Date().addingTimeInterval(-3600)
    let cutoff2 = Date().addingTimeInterval(-86400)
    state.sessions = state.sessions.filter { _, s in
        if let ended = s.endedAt { return ended > cutoff1 }
        return s.lastActivityAt > cutoff2
    }
}
```

## 边角情况

| 情况 | 处理 |
|---|---|
| hook 脚本没装（用户拒绝合并 settings.json） | App 仍能从 cc switch / settings.json 拿全局状态，但 session 列表为空；UI 显示 "Hook 未安装，无法显示会话状态" + 一键安装按钮 |
| jsonl 文件被外部清理（logrotate） | FSEvents 监听到文件 truncate，重置 `lastSize = 0`，下次从头读 |
| 多个 CC 进程并发写 | `>>` 是 append 模式，POSIX 保证单次 write 原子（< 4KB） |
| 行跨 FSEvent 边界（部分写） | 留 partial buffer，下次拼接 |
| hook 进程崩溃 | CC 自己不会因 hook 崩溃而崩，但事件可能丢失；不严重 |
| session_id 不在 sessions 字典里（先收到 MessageDisplay 没收到 SessionStart） | lazy 注册：用 cwd 和 _cc_touchbar 字段构造一个 minimal Session |

## 性能预算

- 单次 hook 调用 < 5 ms（jq + append）
- App 解析单行 JSON < 1 ms
- 流式 MessageDisplay 1 秒可能触发多次，但每次只追加一行，I/O 可接受
- 如果 MessageDisplay 太频繁影响性能，可以在 hook 脚本里 throttle（每 session 200ms 内只 append 一次）
