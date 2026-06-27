# Releases

版本说明。tag 触发 GitHub Actions 自动构建未签名 zip 并发布到 GitHub Releases。

## 0.0.8

可配轮询间隔 + 设置面板交互细化 + 主窗口 padding。

### 功能

- **轮询间隔可配**：设置面板新增「轮询间隔」section，可分别配置
  - Transcript / Git 分支检测：默认 **5s**（原 1.5s），范围 0.5–60s
  - 订阅余额刷新：默认 **30s**，范围 5–3600s
  - 输入框配 `NSNumberFormatter`（`isPartialStringValidationEnabled`），实时拦截非数字 / 多个小数点
  - 输入框右侧 `NSStepper`，步长 1s，点击即时写入并重建定时器（无需再点应用）
  - 「应用」按钮调用统一 `parseInterval` 校验：解析失败或越界弹 `NSAlert`「输入无效」并保留原值
- **路径 / 间隔区域左对齐**：`makePathsSection` / `makeIntervalsSection` 的 `section.alignment` 从 `.width` 改为 `.leading`，标题、标签、控件按 intrinsic 宽度左对齐；间隔行去掉 `horizontalSpacer`
- **主窗口上下 padding**：`headerView.topAnchor` / `footerView.bottomAnchor` 加 ±12pt constant，叠加各自 edgeInsets 18pt，整体内容距窗口边 ≈ 30pt
- **间隔字段样式**：宽度 80pt 居中、`monospacedSystemFont`，应用按钮触发解析 + 范围检查 + 弹窗反馈

### 设计变更

- `PreferenceStore` 新增 `pollIntervalSeconds` / `balanceIntervalSeconds` 属性，getter/setter 内置 clamp，越界值自动夹到范围内
- `TranscriptWatcher` 拆出 `reschedule()`，间隔变化时由 AppDelegate 调用重建定时器
- `AppDelegate` 拆出 `rescheduleBalanceTimer()` + `reapplyIntervals()`，主窗口通过 `onIntervalsChanged` 回调触发
- `MainWindowController` 新增 `pollIntervalField` / `pollIntervalStepper` / `balanceIntervalField` / `balanceIntervalStepper` 弱引用，apply / stepper 变化时双向同步

## 0.0.7

设置面板 + 14 套主题 + HUD 圆角背景层 + Dock 行为修复。

### 功能

- **内联设置面板**：header 右上角新增齿轮按钮，点击切换主面板到设置视图；设置视图含返回按钮、Touch Bar 主题选择、Claude Code / CC Switch DB 路径覆盖；移除了之前的「设置主题」「设置路径」两个底部弹窗。
- **14 套主题**：在原深色 / 浅色基础上新增 12 套：Nord、Dracula、Solarized Dark、Tokyo Night、Gruvbox、Rosé Pine、Sunset、Ocean、Forest、Bubblegum、Synthwave、Crimson。设置面板里每个主题以彩色色块预览，按钮背景 + 文字颜色 = 该主题在 Touch Bar 上的实际渲染效果；当前激活主题带强调色边框 + ✓ 前缀。
- **整条 HUD 圆角背景层**：自定义主题（非默认深色）会在整条 HUD 容器底层绘制圆角（cornerRadius 8）背景层，替代之前每个 item 各自加背景的方案，视觉更整体。
- **provider 行为微调**：去掉 provider 按钮的 bezel 背景，与其它 item 一致；自动宽度上限 400pt，点击切换固定 80pt ↔ 自适应。
- **Dock 行为修复**：补齐 `applicationShouldHandleReopen` / `applicationDidBecomeActive` 兜底。之前关闭主窗口后点 Dock 图标只出现菜单栏、窗口不再出现、菜单项也不响应（因为 `applicationDidFinishLaunching` 卡在 auto-layout 求解循环里 —— 同时修复了 `makeThemeSection` / `makePathsSection` 里 row↔section 的 leading/trailing 约束与 stack view 内部约束冲突的问题）。

### 设计变更

- `Theme` 重构：去掉 `providerBezel` / `providerText` / `itemBackground`，新增 `barBackground: NSColor?` 表示整条 HUD 的背景色；默认深色主题 `barBackground = nil` 沿用系统 Touch Bar 黑底。
- 新增 `NSColor(hex:)` 便利构造器，所有自定义主题颜色用 `#RRGGBB` 字符串声明。
- `MainWindowController` 引入 `MainPanel` 状态机（`.sessions` / `.settings`），`settingsContainer` 固定宽度 600pt、居中。
- `TouchBarController.makeHUDItem` 把所有 HUD item 收纳到单个 `.hud` custom Touch Bar item 里，外层 `NSStackView` 加圆角 + `masksToBounds = true` 让 `barBackground` 不会超出圆角。
- 主窗口 `minSize` 设为 640×400，避免设置面板溢出。

## 0.0.6

升级检测 + GitHub 入口 + 菜单栏。

### 功能

- **检查更新**：调用 GitHub Releases API 拉最新 tag，与 bundle 内 `CFBundleShortVersionString` 语义化版本比较；有新版本时弹窗提示，点「前往下载」打开 `releases/latest`。
- **关于我们**：macOS 菜单栏 cc-touchbar 菜单新增「关于 cc-touchbar」，弹窗展示版本号与仓库地址，附「前往 GitHub」按钮。
- **检查更新菜单**：菜单栏新增「检查更新…」，触发 UpdateChecker。
- **GitHub 入口**：主窗口 header 新增 `</>` GitHub 按钮，点击打开 `github.com/ahao430/cc-touchbar`。
- **菜单栏补齐**：之前 app 没有主菜单（`NSApp.mainMenu` 为空），本次顺手补齐 app 菜单（关于 / 检查更新 / 隐藏 / 隐藏其他 / 退出 ⌘Q）。

### 设计变更

- 新增 `Sources/App/UpdateChecker.swift`：纯 enum 命名空间，封装 GitHub API 调用 + 语义化版本比较（split by `.`，逐段比），URL 为 `https://api.github.com/repos/ahao430/cc-touchbar/releases/latest`
- `UpdateCheckResult` 三态：`.upToDate` / `.newVersionAvailable(current:latest:url:)` / `.error`
- AppDelegate 在 `applicationDidFinishLaunching` 末尾调用 `setupMainMenu()`，构建 app 菜单到 `NSApp.mainMenu`
- GitHub 按钮用 SF Symbol `chevron.left.forwardslash.chevron.right`（`</>`）+ 文本「GitHub」，符合 dev tool 语义

## 0.0.5

点击切换宽度 + DeepSeek 模型名修复 + git 分支检测增强。

### 功能

- **点击切换宽度**：provider / model / gitBranch 改成可点击的 NSButton，默认进入固定宽度模式（500pt），点击切换到自适应（≤400pt）。视觉上呈现"宽-窄"切换。
- **DeepSeek 模型名修复**：transcript 解析即使 assistant 消息没有 usage 字段也读 model 字段，解决 DeepSeek 等通过 OpenAI 兼容协议的供应商 model 显示成 "—" 的问题。
- **model 空值 fallback**：contextModelName / defaultModel 为空字符串时统一显示 "—"。
- **git 分支检测**：启动后立即检测一次；cwd 在仓库子目录时向上递归找最近的 `.git`，避免子目录场景下显示 `—`。

## 0.0.4

Git 分支显示 + 模型名修复 + 布局压缩。

### 功能

- **Git 分支**：HUD 新增 `⎇ main` 字段，显示 focused session 的 git 分支。每 1.5s 自动刷新，切分支后立即更新。
- **模型名修复**：transcript 里的实际模型名优先于 settings.json 的 ANTHROPIC_MODEL，解决深源等供应商不设 ANTHROPIC_MODEL 时模型名缺失问题。切供应商时自动清空旧模型缓存。
- **布局压缩**：模型名上限 100pt、分支名上限 80pt、供应商上限 110pt，长名截断尾部。避免右边按钮被挤出屏外。
- **按钮收紧**：图标按钮 30→28pt。
- **customizationIdentifier 移除**：避免 macOS 缓存旧版 Touch Bar 布局导致新增项不显示。

## 0.0.3

Intel 支持：分别构建 arm64 / x86_64 两个 zip，都发到 release assets。修复 CI 权限问题。

### 功能

- **Intel 支持**：`ARCHS=arm64` + `ARCHS=x86_64` 两轮 `xcodebuild`，各打独立 zip
- **CI 权限修复**：workflow 加 `permissions.contents: write`，确保 release 步骤不会因默认只读 token 失败

### 设计变更

- 放弃 universal binary（xcodebuild 默认只打 host arch 行为），改用两次构建分别产出 arm64 / x86_64 zip
- 两个 zip 同名产品 `.app`，只是包含的 arch 不同；用户按 MacBook 机型下载对应版本

### 限制

- x86_64 构建在 Apple Silicon runner（`macos-15`）上交叉编译；如果 Rosetta 工具链不可用，xcodebuild 会 fallback 失败（GitHub 确认 `macos-15` 支持交叉编译 `x86_64`）
- 当前项目没有自签名公证能力，两个 zip 打开都需要右键放行

## 0.0.2

HUD 信息密度扩展：上下文用量 / 累计 token / cache 命中率 / thinking 预算。

### 功能

- **Touch Bar 上下文用量**：解析当前 focused session 的 transcript JSONL，取最近一条 assistant message 的 `usage`，显示 `ctx 78%`（接近 80% 标 ⚠︎，95% 标 ‼︎）。tooltip 显示绝对值与模型。模型上限按名字推断（`1m` / `gemini` → 1M；默认 200k）。
- **累计 billed tokens**：账单口径 `input + creation×1.25 + read×0.1 + output` 累加整个 session，显示 `Σ 1.2M ⚡92%`。tooltip 显示轮数与详细公式。
- **Cache 命中率**：最近一轮 `cache_read / (input + cache_read + cache_creation)`，拼在 `Σ` 字段尾部，闪电符号区分。
- **Thinking 预算**：读 `~/.claude/settings.json` 的 `MAX_THINKING_TOKENS`，显示 `💭 32k`，tooltip 标注档位（think / megathink / think harder / ultrathink）。未设置则该字段空白。
- **分隔线**：在 `[provider·model] │ [balance] │ [ctx·Σ·thinking] │ [buttons]` 之间画 1.5pt 竖线，颜色跟随主题。
- **按钮收紧**：app / cc switch / collapse 三按钮统一 `.inline` bezel + 30pt 宽度约束，图标保持 18×18，避免 cc switch 按钮被挤出屏外。
- **供应商按钮宽度上限**：130pt + 尾部截断 + tooltip 显示完整名。

### 设计变更

- 数据通路复用 `SessionStore.focusedSession.transcriptPath`；新增 `TranscriptWatcher` 1.5s tail transcript JSONL
- 上下文上限按模型名启发式推断；后续如需更精确的映射集中在 `TranscriptWatcher.contextLimit(for:)`
- Cache 命中率选「最近一轮」而非累计：用户能看到 cache 冷启动 / 中断时的瞬时变化

### 限制

- `MAX_THINKING_TOKENS` 字段未设置时 thinking 字段是空字符串（NSTextField 仍占微小宽度）；彻底隐藏需要按 state 重建 NSTouchBar
- `/fast` 是 Claude Code 运行时 toggle，不落盘 settings.json，无法读到 Touch Bar

## 0.0.1

首次可用版本。Touch Bar HUD + 三层数据源 + Hook 接入 + DFR 常驻。

### 功能

- **Touch Bar HUD**：provider / 模型 / 订阅余额（含刷新剩余时间）/ cc-touchbar 与 cc switch 快捷按钮 / collapse（最小化到 Control Strip）
- **三层数据源**：自动识别官方订阅（L1）/ 第三方 env vars（L2）/ cc switch（L3）；`settings.json` 变化时自动重算
- **DFR 系统级呈现**：通过私有 DFR API 让 HUD 在切到其它 app 时仍可见；Control Strip 里常驻 tray 图标，点击重新展开
- **cc switch 只读 Bridge**：activeProvider / providers 列表 / Zhipu 订阅余额（含周期百分比 + 距离下次刷新的剩余时间）
- **Hook 接入层**：自动安装 dispatcher 脚本到 `~/.claude/cc-touchbar-dispatcher.sh`，合并 `settings.json` 的 hooks 块（不覆盖用户已有 hooks）；JSONL 文件通道实时推送 session 状态
- **多会话追踪**：sessions 字典 + NSWorkspace 焦点联动；主窗口列表展示全部活动会话
- **窗口激活**：iTerm / Terminal.app / tmux 优先；其它宿主走 PID fallback
- **主题**：深色（默认）/ 浅色两套；主窗口一键切换，立即推到 Touch Bar
- **路径手动覆盖**：Claude binary / cc switch DB 都支持自动检测 + 手动覆盖（NSOpenPanel）+ 一键清除
- **诊断面板**：启动时收集机型 / 路径 / 数据源 / hook 状态，便于排障

### 设计变更（相对最初规划）

- DFR 从 v3 后期提前到当前版本（没有它切到其它 app HUD 就消失了）
- 移除 Touch Bar 上的 duration（运行时间）字段和 close 按钮（用 collapse 替代）
- 主题系统先打通 2 套 + 切换链路；完整版（5 套预设 + 自定义 + 导入导出）进路线图
- Provider 文字用 `attributedTitle` 强制白色（disabled `NSButton` 会被系统变灰）

### 限制

- 仅签名 `-`（自签），首次打开需手动放行（右键打开或 `xattr -dr com.apple.quarantine`）
- 仅支持带 Touch Bar 的 MacBook（MacBook Pro 2016–2019 Intel + 2020 M1 13"）
- 余额的"刷新剩余时间"目前仅 Zhipu 渠道可读（依赖其 `/api/monitor/usage/quota/limit` 暴露的 `nextResetTime`）

### 已知 TODO（→ [ROUTES_MAP.md](ROUTES_MAP.md)）

- Touch Bar 状态文字字段（thinking / streaming / idle）
- provider popover + 健康状态
- 完整主题系统（3 套预设 + 自定义 + 导入导出）
- 直写 SQLite 切 provider
- 完整跨终端激活（Ghostty / WezTerm / VS Code URL scheme）
- 多 app_type（codex / gemini）
- 使用分析图表
