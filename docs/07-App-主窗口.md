# 07 - App 主窗口

> 主窗口是用户管理多个 Claude Code 会话的控制台：看全局状态、查看所有活动会话、点击激活任一会话对应的终端/IDE 窗口。

## 布局

```
┌──────────────────────────────────────────────────────────────┐
│  cc-touchbar                                       [偏好设置] │
├──────────────────────────────────────────────────────────────┤
│  全局状态                                                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ [Zhipu GLM（包年订阅）]  [glm-5.2]                     │  │
│  │ 数据源: cc switch                                       │  │
│  │ [$1.23 today]  [$28.50 month]  5/1000 reqs today       │  │
│  │ proxy: 127.0.0.1:15721                                 │  │
│  └────────────────────────────────────────────────────────┘  │
│  （L1/L2 下隐藏 cost/proxy 字段）                              │
├──────────────────────────────────────────────────────────────┤
│  活动会话 (3)                                       [刷新]     │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ ● cc-touchbar                                           ││
│  │   ~/workspace/cc-touchbar                               ││
│  │   iTerm.app · streaming · 刚刚              [Activate ▸] ││
│  ├──────────────────────────────────────────────────────────┤│
│  │ ○ blog-redesign                                         ││
│  │   ~/workspace/blog                                      ││
│  │   VS Code · idle · 12 分钟前                [Activate ▸] ││
│  ├──────────────────────────────────────────────────────────┤│
│  │ ● api-refactor                                          ││
│  │   ~/workspace/api                                       ││
│  │   Ghostty · thinking · 30 秒前              [Activate ▸] ││
│  └──────────────────────────────────────────────────────────┘│
├──────────────────────────────────────────────────────────────┤
│  [打开 cc switch]   状态: ready · 上次刷新: 14:23:05         │
│  （L1/L2 下隐藏 cc switch 按钮）                              │
└──────────────────────────────────────────────────────────────┘
```

## 三个功能区

### 1. 顶部全局状态条

| 字段 | 来源 | L1 | L2 | L3 |
|---|---|---|---|---|
| 数据源标签 | `state.activeSource` | "官方订阅" | "第三方模型" | "cc switch" |
| Provider 名 | `state.provider?.name` | "Claude Official" | 友好名映射 | SQLite |
| Model | `state.modelMapping?.defaultModel` | env/默认 | env | env |
| 今日 cost | `state.costToday` | 隐藏 | 隐藏 | SQLite |
| 本月 cost | `state.costMonth` | 隐藏 | 隐藏 | SQLite |
| 今日请求数 | `state.requestCountToday` | hook 自算 | hook 自算 | SQLite |
| Proxy 地址 | `state.ccSwitch.proxyConfig` | 隐藏 | 隐藏 | SQLite |

### 2. 中部会话列表

每行 = 一个 `Session`：

| 字段 | 来源 | 备注 |
|---|---|---|
| 状态点 | `session.status` | 🟢 streaming / 🟡 thinking / 🔵 idle / 🔴 error / ⚪ ended |
| 项目名 | `session.cwd.lastPathComponent` | 主标识 |
| 完整路径 | `session.cwd.path` | 次行灰字 |
| 宿主 app | `session.hostApp` | iTerm.app / VS Code / Ghostty |
| 状态 | `session.status.rawValue` | streaming / thinking / idle |
| 最近活动 | `session.lastActivityAt` 相对时间 | "刚刚 / 12 分钟前"，每秒刷新 |
| Activate 按钮 | 触发窗口激活 | 行点击等效 |

### 3. 底部状态栏

- 打开 cc switch（按钮，仅 L3）
- 刷新（按钮，强制 Poller.tick）
- App 自身状态：`ready / refreshing / error`
- 上次刷新时间

## 交互

### 点击行 / Activate 按钮

```swift
func activate(_ session: Session) {
    do {
        try WindowActivator.activate(session)
    } catch {
        showError("无法激活窗口：\(error)")
    }
}
```

### 双击行

激活 + 关闭 App 主窗口（类似 Spotlight 的"搜到即走"）。

### 右键菜单

```
Activate              [默认]
─────────────────────
Copy cwd path
Open in Finder
Open in Terminal (new tab)
─────────────────────
Show in cc switch     （仅 L3，跳到对应 provider 详情）
─────────────────────
End session...        [危险，需确认]
```

### 长按 status 项（Touch Bar 集成）

Touch Bar 上长按 status 项 → popover 显示同样的列表，点选项 = Activate。

## Window Activator

### 协议

```swift
protocol WindowActivating {
    func activate(_ session: Session) throws
}

enum ActivationError: Error {
    case hostAppNotRunning
    case tabNotFound(String)
    case appleScriptFailed(String)
    case unsupportedHostApp(String)
}
```

### 实现：按 hostApp 分发

```swift
struct WindowActivatorImpl: WindowActivating {
    func activate(_ session: Session) throws {
        switch session.hostApp {
        case .iterm:        try activateITerm(session)
        case .terminalApp:  try activateTerminalApp(session)
        case .ghostty:      try activateGhostty(session)
        case .wezterm:      try activateWezterm(session)
        case .vscode, .cursor:
                            try activateVSCode(session)
        case .unknown:      try activateByParentPID(session)
        }

        if let pane = session.tmuxPane {
            try? tmuxSelectPane(pane)
        }
    }
}
```

### iTerm AppleScript

```applescript
tell application "iTerm"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            try
                if (id of session of t) = "<term_session_id>" then
                    select t
                    set index of w to 1
                    return
                end if
            end try
        end repeat
    end repeat
end tell
```

### Terminal.app AppleScript

```applescript
tell application "Terminal"
    activate
    repeat with w in windows
        repeat with t from 1 to count of tabs of w
            if (name of tab t of w) contains "<project_basename>" then
                set selected tab of w to tab t of w
                set index of w to 1
                return
            end if
        end repeat
    end repeat
end tell
```

### VS Code

```swift
func activateVSCode(_ session: Session) throws {
    // 1. URL scheme
    let urlStr = "vscode://file\(session.cwd.path)"
    if let url = URL(string: urlStr) {
        NSWorkspace.shared.open(url)
        return
    }

    // 2. fallback：找 VS Code 进程，activate
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode").first {
        app.activate(options: [.activateAllWindows])
        return
    }

    throw ActivationError.hostAppNotRunning
}
```

> Cursor 的 bundle id 是 `com.todesktop.230313mzl4w4u92`，Windsurf 也有自己的。`hostApp` 枚举里要分别处理。

### Ghostty

```bash
ghostty +focus-window --tab-id=<tab_id>
```

### WezTerm

```bash
wezterm cli focus-pane --pane-id <pane_id>
```

### tmux

```swift
func tmuxSelectPane(_ paneId: String) throws {
    let _ = try ShellRunner.run(
        command: "tmux select-pane -t \(paneId) && tmux select-window -t \(paneId)",
        timeout: 1
    )
}
```

tmux 切 pane 后，宿主终端窗口仍需要单独激活（Window Activator 上层调用顺序：先 tmux 切 pane，再激活宿主 app）。

### Fallback：按父进程 PID

```swift
func activateByParentPID(_ session: Session) throws {
    let pids = processChain(from: session.ppid)
    for pid in pids {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
            return
        }
    }
    throw ActivationError.hostAppNotRunning
}
```

## 状态指示器

每秒 timer 刷新相对时间显示：

```swift
func relativeTime(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 5 { return "刚刚" }
    if s < 60 { return "\(s) 秒前" }
    if s < 3600 { return "\(s/60) 分钟前" }
    return "\(s/3600) 小时前"
}
```

## 边角情况

| 情况 | 处理 |
|---|---|
| 点击的 session 已 SessionEnd | 行变灰，Activate 按钮禁用，提示 "会话已结束" |
| 宿主 app 已退出（iTerm 关了） | AppleScript 失败 → fallback 用 Terminal 打开 cwd |
| VS Code 窗口已关闭 | URL scheme 打开新窗口 |
| 多个 session 同一窗口（tmux 多 pane） | tmux select-pane 切到目标 pane，宿主窗口拉前 |
| CC 在 SSH 远端跑（罕见） | 无法激活远端窗口，行显示 `remote · <host>`，按钮禁用 |
| 用户拒绝授权 AppleScript | 首次激活时弹权限对话框，拒绝后所有终端激活降级到 PID fallback |

## v2 / v3 拆分

| 阶段 | 范围 |
|---|---|
| **v2** | 会话列表 + Activate 按钮（iTerm + Terminal.app + tmux 优先，其它 hostApp 走 PID fallback） |
| **v3** | 完整跨终端支持（Ghostty / WezTerm / VS Code URL scheme）、右键菜单、远程 session 检测、tmux 多 pane 精细切换 |

## 主窗口 vs Touch Bar 的关系

两者都消费同一个 `AppState`：

| 字段 | 主窗口 | Touch Bar |
|---|---|---|
| 全局状态 | 顶部条 | 主行 |
| 会话列表 | 中部表格 | 长按 status 弹 popover |
| Activate 动作 | 行点击 | popover 项点击 |

数据一致，UI 形态不同。任何一处操作（如 Touch Bar 选了某个 session），主窗口也会同步高亮。
