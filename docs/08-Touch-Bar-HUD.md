# 08 - Touch Bar HUD

> Touch Bar 是无状态 UI：只渲染 `AppState` 下发的数据。不开定时器、不读文件、不查数据库。

## 仅支持带 Touch Bar 的 MacBook

App 启动时检测机型，不支持就退出。详见 [02-环境探测.md](02-环境探测.md)。

不做的：

- ❌ 菜单栏模式（`LSUIElement = YES`）
- ❌ App 窗口镜像 Touch Bar 内容作为"无 Touch Bar 设备的 fallback"
- ❌ Touch Bar 模拟器适配

App 主窗口存在，但它是管理界面（设置 / 会话列表 / 窗口激活），不是 Touch Bar 的 fallback。

## 布局（按数据源层级变化）

最左永远是 Claude Code 图标（`appIcon`），状态联动。详见下方"图标状态联动"。

### L1 官方订阅

```
[ ✳ ] [ Claude Official ] [ sonnet-4.5 ] [ status ] [ 5m ] [ ⚙ ]
```

### L2 第三方 env vars

```
[ ✳ ] [ Zhipu GLM ] [ glm-5.2 ] [ status ] [ 5m ] [ ⚙ ]
```

### L3 cc switch

```
[ ✳ ] [ Zhipu GLM（包年订阅） ] [ glm-5.2 ] [ status ] [ 5m ] [ $cost ] [ ⚙ ] [ ↹ ]
```

## 会话计时

紧跟 `status` 之后，显示当前 focused session 的已运行时长（从 SessionStart hook 触发开始）。

### 格式化

| 时长       | 显示            |
| ---------- | --------------- |
| < 1 分钟   | `just now`    |
| 1-59 分钟  | `5m`、`23m` |
| 1-23 小时  | `1h 5m`       |
| >= 24 小时 | `1d 2h`       |

### 数据来源

`session.startedAt`（SessionStart hook 时记录，详见 [05-hook-接入层.md](05-hook-接入层.md)）。

### 更新频率

- **默认**：30 秒 timer，分钟粒度（省电）
- **详细模式**（偏好设置开启）：1 秒 timer，秒粒度 `5m 23s`

### 行为

| 情况                                    | 显示                                                      |
| --------------------------------------- | --------------------------------------------------------- |
| 正常运行                                | 实时计时                                                  |
| 用户切 focused session                  | 立即切到对应 session 的 startedAt                         |
| SessionEnd 触发                         | 冻结最后值，加`· ended` 标记                           |
| 用户开新 CC 窗口                        | 新 session_id 自动从 0 开始计时                           |
| App 重启                                | 从 hook 推上来的 SessionStart 事件恢复（前提：CC 还在跑） |
| focused session 为空（无 session 数据） | 显示`—`                                                |

### 实现

```swift
final class SessionDurationFormatter {
    static func format(
        startedAt: Date,
        now: Date = Date(),
        endedAt: Date? = nil,
        detailed: Bool = false
    ) -> String {
        if let ended = endedAt {
            let dur = ended.timeIntervalSince(startedAt)
            return "\(formatDuration(dur, detailed: detailed)) · ended"
        }
        return formatDuration(now.timeIntervalSince(startedAt), detailed: detailed)
    }

    private static func formatDuration(_ seconds: TimeInterval, detailed: Bool) -> String {
        let s = Int(seconds)
        if detailed {
            if s < 60 { return "\(s)s" }
            let m = s / 60
            if m < 60 { return "\(m)m \(s % 60)s" }
            let h = m / 60
            return "\(h)h \(m % 60)m"
        } else {
            if s < 60 { return "just now" }
            let m = s / 60
            if m < 60 { return "\(m)m" }
            let h = m / 60
            if h < 24 { return "\(h)h \(m % 60)m" }
            return "\(h / 24)d \(h % 24)h"
        }
    }
}
```

### Timer

```swift
final class DurationTimer {
    weak var state: AppState?
    private var timer: Timer?

    func start() {
        let interval: TimeInterval = prefs.detailedDuration ? 1 : 30
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.state?.touchBarReload(.duration)
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
}
```

### 触发刷新

| 字段变化                           | reload 范围                                |
| ---------------------------------- | ------------------------------------------ |
| 30s / 1s timer tick                | `.duration`                              |
| `focusedSessionID` 变化          | `.duration`（立即切到新 session 的时长） |
| focused session 的`endedAt` 变化 | `.duration`（加 ended 标记）             |

### 边角情况

- **session 跨天**：显示 `1d 2h`，不显示完整日期（用户在 statusline 里已经能看到 startedAt 时间戳）
- **App 长期运行**：duration timer 30s 一次，内存稳定
- **多个长 session（>24h）**：用户可能忘了关；列表里可以加"提示关闭"按钮（v3）

## 图标状态联动

最左的 `appIcon` 是一个会动的 Claude Code 图标，根据当前 focused session 的 status 切换动画。

### 状态动画表

| `session.status`         | 动画                                            | 视觉感受   |
| -------------------------- | ----------------------------------------------- | ---------- |
| `idle`                   | 静止                                            | 等待输入   |
| `thinking`               | 脉冲缩放 1.0 → 1.15（0.8s 周期，缓动）         | "正在想"   |
| `streaming`              | 360° 旋转（2s）+ 透明度脉冲 0.6 → 1.0（0.5s） | "正在输出" |
| `error`                  | 红色 tint + 一次性左右抖动（0.4s）              | 出错了     |
| `unknown` / setup 未完成 | 40% 透明度静止                                  | 未就绪     |

### 图标素材优先级

```swift
func resolveIconImage() -> NSImage {
    // 1. 用户偏好设置里指定的本地图片（PNG / GIF）
    if let custom = prefs.customIconURL,
       let img = NSImage(contentsOf: custom) {
        return img
    }

    // 2. 内置 Claude 风格花型（CGPath 矢量绘制，无素材依赖）
    return内置ClaudeFlower(size: 30)

    // 3. SF Symbol sparkles 兜底（理论上不会走到这里）
}
```

### 点击行为

- **单击** = `openApp`（和 ⚙ 等效，最左更顺手）
- **长按** = 显示 sessions popover（和长按 status 项等效）

### 实现核心

`StatusIconView`（自定义 `NSView`，包一个 `CALayer`）：

```swift
final class StatusIconView: NSView {
    private let iconLayer = CALayer()
    private weak var state: AppState?
    private var observers: Set<AnyCancellable> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(iconLayer)
        iconLayer.contents = resolveIconImage().layerImage
        iconLayer.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    func bind(to state: AppState) {
        self.state = state
        state.$focusedSessionID.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateAnimation() }
        }.store(in: &observers)
    }

    private func updateAnimation() {
        iconLayer.removeAllAnimations()
        let status = state?.focusedSession?.status ?? .unknown

        switch status {
        case .idle, .unknown:
            iconLayer.opacity = (status == .unknown) ? 0.4 : 1.0

        case .thinking:
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.0
            pulse.toValue = 1.15
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iconLayer.add(pulse, forKey: "thinking")

        case .streaming:
            let rotation = CABasicAnimation(keyPath: "transform.rotation")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 2.0
            rotation.repeatCount = .infinity
            iconLayer.add(rotation, forKey: "rot")

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.6
            opacity.toValue = 1.0
            opacity.duration = 0.5
            opacity.autoreverses = true
            opacity.repeatCount = .infinity
            iconLayer.add(opacity, forKey: "pulse")

        case .error:
            iconLayer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3).cgColor
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [-3, 3, -2, 2, 0]
            shake.duration = 0.4
            iconLayer.add(shake, forKey: "shake")
        }
    }
}
```

### 与 status 项的关系

`appIcon` 和 `status` 字段共享同一个数据源（`state.focusedSession?.status`）：

- `appIcon` 是**视觉**呈现（动画）
- `status` 是**文字 + 颜色**呈现（streaming / idle / 等）

两者同步更新，用户既可以看到动画也能看到文字。

### Touch Bar 注册

`appIcon` 在所有层级（L1/L2/L3）都显示，作为最左固定项：

```swift
override func makeTouchBar() -> NSTouchBar? {
    var items: [NSTouchBarItem.Identifier] = [.appIcon, .provider, .model, .status, .cwd]
    // ... 其它项按层级追加
    bar.defaultItemIdentifiers = items
    return bar
}

extension NSTouchBarItem.Identifier {
    static let appIcon = NSTouchBarItem.Identifier("cc-touchbar.appIcon")
}
```

### 性能预算

- CALayer 动画 GPU 加速，CPU 几乎零开销
- 状态切换 < 16ms（一帧内完成）
- 不需要 timer（CABasicAnimation 自带 timing）

## 各项

| Identifier         | 视图                           | 数据来源                                        | L1   | L2   | L3 |
| ------------------ | ------------------------------ | ----------------------------------------------- | ---- | ---- | -- |
| `appIcon`        | `StatusIconView`（动画图标） | `state.focusedSession?.status`                | ✅   | ✅   | ✅ |
| `provider`       | `NSButton`（标题，禁用）     | `state.provider?.name`                        | ✅   | ✅   | ✅ |
| `model`          | label                          | `state.modelMapping?.defaultModel`            | ✅   | ✅   | ✅ |
| `status`         | 带颜色 label                   | `state.focusedSession?.status`                | ✅   | ✅   | ✅ |
| `duration`       | label                          | `state.focusedSession?.startedAt` 计算时长    | ✅   | ✅   | ✅ |
| `cwd`            | label                          | `state.focusedSession?.cwd.lastPathComponent` | ✅   | ✅   | ✅ |
| `cost`           | label                          | `state.costToday` 格式化 `$X.XX`            | 隐藏 | 隐藏 | ✅ |
| `costMonth`      | label（次行）                  | `state.costMonth`                             | 隐藏 | 隐藏 | ✅ |
| `openApp`        | `NSButton`                   | `NSApp.activate(ignoringOtherApps: true)`     | ✅   | ✅   | ✅ |
| `openCCS`        | `NSButton`                   | `NSWorkspace.open(CC Switch.app)`             | 隐藏 | 隐藏 | ✅ |
| `switchProvider` | popover                        | `state.availableProviders` 列表               | 隐藏 | 隐藏 | ✅ |
| `sessions`       | popover（长按 status）         | `state.sessions.values`                       | ✅   | ✅   | ✅ |

## 颜色映射

> ⚠️ 颜色受主题影响，下面是默认 Classic 主题的值。其它主题（Cyberpunk / Pastel 等）的颜色从 `ThemeStore.current.colors` 读取。详见 [11-主题系统.md](11-主题系统.md)。

```swift
extension SessionStatus {
    func displayColor(theme: Theme, appearance: NSAppearance) -> NSColor {
        switch self {
        case .idle:      return theme.colors.statusIdle.resolve(for: appearance)
        case .thinking:  return theme.colors.statusThinking.resolve(for: appearance)
        case .streaming: return theme.colors.statusStreaming.resolve(for: appearance)
        case .error:     return theme.colors.statusError.resolve(for: appearance)
        case .unknown:   return theme.colors.statusUnknown.resolve(for: appearance)
        }
    }

    var displayText: String {
        switch self {
        case .idle:      return "idle"
        case .thinking:  return "thinking"
        case .streaming: return "streaming"
        case .error:     return "error"
        case .unknown:   return "—"
        }
    }
}
```

### Classic 主题默认色

| 状态      | hex                   |
| --------- | --------------------- |
| idle      | `#999999`（系统灰） |
| thinking  | `#FFD60A`（系统黄） |
| streaming | `#30D158`（系统绿） |
| error     | `#FF3B30`（系统红） |
| unknown   | `#999999`           |

## 接线

### TouchBarController

```swift
final class TouchBarController: NSObject, NSTouchBarDelegate {
    weak var state: AppState?
    private var observers: Set<AnyCancellable> = []
    private var touchBar: NSTouchBar?

    func setup(state: AppState) {
        self.state = state
        observeState()
    }

    private func observeState() {
        guard let state else { return }

        state.$focusedSessionID.sink { [weak self] _ in
            self?.touchBar?.reload(.status, .duration, .cwd)
        }.store(in: &observers)

        state.$costToday.sink { [weak self] _ in
            self?.touchBar?.reload(.cost)
        }.store(in: &observers)

        state.$provider.sink { [weak self] _ in
            self?.touchBar?.reload(.provider, .model)
        }.store(in: &observers)

        // activeSource 变化 → 整 bar 重建（项的可用性变了）
        state.$activeSource.sink { [weak self] _ in
            self?.rebuildTouchBar()
        }.store(in: &observers)
    }
}
```

### makeTouchBar（按 activeSource 决定项）

```swift
override func makeTouchBar() -> NSTouchBar? {
    let bar = NSTouchBar()
    bar.delegate = self

    var items: [NSTouchBarItem.Identifier] = [.provider, .model, .status, .cwd]

    if state?.activeSource == .ccSwitch {
        items.append(.cost)
    }

    items.append(.flexibleSpace)
    items.append(.openApp)

    if state?.activeSource == .ccSwitch {
        items.append(.openCCS)
    }

    bar.defaultItemIdentifiers = items
    bar.customizationIdentifier = "cc-touchbar-main"
    bar.customizationAllowedItemIdentifiers = items
    self.touchBar = bar
    return bar
}
```

### 各 item 的 view 构造

```swift
func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
    switch identifier {
    case .provider:
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: state?.provider?.name ?? "—", target: nil, action: nil)
        button.isEnabled = false
        item.view = button
        return item

    case .status:
        let popover = NSPopoverTouchBarItem(identifier: identifier)
        let session = state?.focusedSession
        popover.collapsedRepresentationLabel = session?.status.displayText ?? "—"
        popover.collapsedRepresentationColor = session?.status.displayColor ?? .systemGray
        popover.popoverShowClosure = { [weak self] in self?.buildSessionListPopover() }
        return popover

    case .openApp:
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: "⚙", target: self, action: #selector(openApp))
        item.view = button
        return item

    case .openCCS:
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: "↹", target: self, action: #selector(openCCSwitch))
        item.view = button
        return item

    // ...
    }
}
```

## Popover：长按 status 显示会话列表

```swift
private func buildSessionListPopover() -> NSViewController {
    let vc = NSViewController()
    let stack = NSStackView()
    stack.orientation = .vertical

    for session in (state?.sessions.values ?? []).sorted(by: { $0.lastActivityAt > $1.lastActivityAt }) {
        let row = SessionRowButton(session: session) { [weak self] in
            try? self?.windowActivator.activate(session)
            self?.dismissPopover()
        }
        stack.addArrangedSubview(row)
    }

    vc.view = stack
    return vc
}
```

## HUD 不显示的情况

| 情况                             | HUD 显示                                                              |
| -------------------------------- | --------------------------------------------------------------------- |
| Setup 未完成                     | `[ setup required ] [⚙]`                                           |
| 数据源未确定                     | `[ detecting... ] [⚙]`                                             |
| Hook 未安装（无会话数据）        | provider + model 正常显示；status 显示`—`；点 status 提示安装 hook |
| 全部 session ended               | provider + model 正常显示；status 显示`idle`（fallback 全局）       |
| cc switch db schema 不兼容（L3） | `[ error ] [↹]`，点 error 显示详情；可手动切到 L1/L2               |

## 触发刷新的策略

**按字段 reload，不重建整 bar**（除非 `activeSource` 变了）。

| 字段变化                                     | reload 范围                                        |
| -------------------------------------------- | -------------------------------------------------- |
| `provider`                                 | `.provider`, `.model`                          |
| `modelMapping`                             | `.model`                                         |
| `costToday`                                | `.cost`                                          |
| `costMonth`                                | `.costMonth`                                     |
| `focusedSessionID`                         | `.status`, `.duration`, `.cwd`, `.appIcon` |
| `sessions[id].status`（且 id == focused）  | `.status`, `.appIcon`                          |
| `sessions[id].endedAt`（且 id == focused） | `.duration`（加 ended 标记）                     |
| duration timer tick                          | `.duration`                                      |
| `sessions` 整体                            | popover 内容（下次展开时重建）                     |
| `activeSource`                             | **整 bar 重建**                              |

## 触感反馈

激活按钮按下时用 `NSHapticFeedbackManager`：

```swift
NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
```

## App 窗口失焦时

Touch Bar 默认显示 frontmost app 的 bar。当 cc-touchbar 不是 frontmost 时：

- 用户在终端 / IDE 里工作时 → Touch Bar 显示那个 app 的 bar（终端自己的）
- 但 cc-touchbar 的 Touch Bar HUD **仍可以通过 `DFR`**（Dynamic Function Row）显示

> Touch Bar 上有个独立区域叫"控制条"（control strip），可以永久显示一个按钮，点击唤起 cc-touchbar 的完整 HUD。这是 Apple 提供的 `NSSystemInfo` / `DFR` API。
>
> v2 阶段探索。v1 先让用户按 fn 切换 Touch Bar 模式看到 cc-touchbar HUD（即 cc-touchbar 必须是 frontmost 时才显示）。
