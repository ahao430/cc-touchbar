# Releases

版本说明。tag 触发 GitHub Actions 自动构建未签名 zip 并发布到 GitHub Releases。

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
