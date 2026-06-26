# cc-touchbar 文档

> Claude Code 工作流的 macOS Touch Bar HUD。
>
> **App 拥有状态；Touch Bar 是无状态 UI；cc switch 是可选增强。**
>
> **本项目仅支持带 Touch Bar 的 MacBook 机型**（MacBook Pro 2016–2019 Intel + 2020 M1 13"）。

## 核心设计原则（承重墙）

- **Touch Bar = 无状态 UI。** 只渲染 App 下发的数据。不读文件、不查数据库、不开定时器。
- **App = 状态拥有者。** discovery / 轮询 / hook 接入 / 窗口激活全部在这里。
- **三层数据源策略。** 官方订阅 → 第三方模型（env vars） → cc switch，按层级递进。
- **单一数据源。** 一个 `AppState` 可观察对象同时驱动 App 窗口和 Touch Bar。
- **失败要响亮，失败要兜底。** 任一数据源缺失时，HUD 对应字段显示 `—`，不崩溃。

## 文档索引

| 文档                                          | 内容                                                         |
| --------------------------------------------- | ------------------------------------------------------------ |
| [01-架构总览.md](01-架构总览.md)                 | 整体架构、模块划分、数据流、`AppState` 数据模型            |
| [02-环境探测.md](02-环境探测.md)                 | Claude Code binary 探测、官方订阅检测、cc switch 可选探测    |
| [03-数据源策略.md](03-数据源策略.md)             | **三层优先级**：官方订阅 / 第三方 env vars / cc switch |
| [04-cc-switch-桥接层.md](04-cc-switch-桥接层.md) | SQLite 只读 Bridge、关键查询、WAL 注意事项                   |
| [05-hook-接入层.md](05-hook-接入层.md)           | Claude Code hooks → JSONL → App 实时通道                   |
| [06-多窗口追踪.md](06-多窗口追踪.md)             | 多窗口/会话追踪、焦点切换、跨终端矩阵                        |
| [07-App-主窗口.md](07-App-主窗口.md)             | App 主窗口、会话列表、窗口激活机制                           |
| [08-Touch-Bar-HUD.md](08-Touch-Bar-HUD.md)       | Touch Bar HUD 布局、各项数据来源、popover                    |
| [10-风险与待办.md](10-风险与待办.md)             | 风险登记表、待办问题                                         |
| [11-主题系统.md](11-主题系统.md)                 | 多套主题切换（颜色 / 图标 / 字体）、自定义、导入导出         |

## 三层数据源（详见 03-数据源策略.md）

| 层级                    | 数据源                                | 何时启用                          | 提供什么                                                |
| ----------------------- | ------------------------------------- | --------------------------------- | ------------------------------------------------------- |
| **L1 官方订阅**   | Anthropic 官方账号                    | settings.json 无 env 覆盖         | 订阅状态（Pro/Max）、用量统计（来自 hook + transcript） |
| **L2 第三方模型** | `~/.claude/settings.json` 的 env 块 | 用户手动配置了 ANTHROPIC_BASE_URL | provider 名（从 BASE_URL 推断）、model 映射             |
| **L3 cc switch**  | `cc-switch.db` SQLite               | 装了 cc switch                    | 完整 provider 列表、cost、健康状态、切换能力            |

App 自动按层级解析当前激活数据源。**装了 cc switch 是增强，不是必须**。

## 实现状态（2026-06-26）

> 详细分项与 TODO 路线图见 [../ROUTES_MAP.md](../ROUTES_MAP.md)。本节只给概览。

### 已完成

- **Touch Bar 机型检测**：启动时校验，不支持就弹窗退出
- **Claude Code 路径解析**：登录 shell `which claude`（nvm 兼容）+ nvm 目录扫描 + 手动覆盖
- **cc switch 路径解析**：`app_paths.json` override + 默认路径 + 手动覆盖
- **三层数据源识别**：`SourceResolver` + `settings.json` FSEvents 监听
- **cc switch 只读 Bridge**：activeProvider / providers / 余额（含 Zhipu `nextResetTime` 续期剩余时间）
- **Hook 接入层**：dispatcher 脚本安装 + `settings.json` hooks 注册 + JSONL 解析
- **多会话追踪**：sessions 字典 + NSWorkspace 焦点联动 + AppleScript / PID 激活
- **主窗口**：会话列表 + provider/model/source chip + 诊断 / 路径 / 主题 footer 按钮
- **Touch Bar HUD**：appIcon + provider + model + balance + openApp + openCCSwitch + collapse
- **DFR 常驻**：私有 DFR API 做系统模态呈现 + Control Strip tray 图标
- **基础主题**：深色 / 浅色两套，主窗口一键切换并实时推到 Touch Bar

### 已规划但 TODO（→ 路线图）

- **Touch Bar 状态文字 + cwd**：当前只有动画 status icon；计划加文字 status / cwd 字段
- **provider popover + 健康状态**：Touch Bar + 主窗口
- **主题系统完整化**：剩 3 套预设（Cyberpunk / Pastel / Terminal Green）+ 自定义 + 导入导出
- **直写 SQLite 切 provider**：需先逆向 cc-switch reload 机制
- **多 app_type**：codex / gemini
- **使用分析图表**
- **完整跨终端激活**：Ghostty / WezTerm / VS Code URL scheme

## 与原始设计的关键差异

> 以下是落地过程中相对最初设计文档做的调整。

| 模块 | 原设计 | 落地版本 | 原因 |
|---|---|---|---|
| **DFR** | v3 远期才做 | 提前到当前版本 | 私有 API 实测稳定；没有 DFR 的话切到其它 app HUD 就消失了，核心体验过不去 |
| **Touch Bar 运行时间（duration）** | v2 范围 | 已移除 | 实际使用中价值低，Touch Bar 空间紧张 |
| **Touch Bar 关闭按钮** | 一直保留 | 已移除，改为 collapse（最小化到 Control Strip） | 关闭=消失，用户找不到入口；collapse 更符合 macOS 习惯 |
| **Touch Bar status / cwd 文字** | 已实现 | 暂未实现，TODO | 节省空间；先用主窗口列表承载 |
| **主题系统** | 5 套预设 + 自定义 + 导入导出 | 先落地 2 套（dark / light），完整版 TODO | 颜色 / 字体 / 图标 tint / glow 这套体系复杂度高，先打通"主题切换链路"再加内容 |
| **Provider 文字颜色** | 主题控制 | 用 `attributedTitle` 强制白色 | disabled `NSButton` 会被系统强制变灰，普通 `textColor` / `contentTintColor` 都压不住 |
| **订阅余额** | 只显示 cost | 增加"刷新剩余时间"（基于 Zhipu `nextResetTime`） | 用户更关心"还有多久刷新额度"而不是已花了多少 |
| **provider 友好名映射** | 内置一张 host → name 表 | 走 cc switch 的 `name` 字段；L2 仍用 hostname fallback | cc switch 里已经有用户自定义的中文名，比硬编码表更准 |

## MVP 时间线一览

| 阶段         | 数据源          | 目标                                        | 状态 |
| ------------ | --------------- | ------------------------------------------- | ---- |
| **v1** | L1 官方订阅     | Touch Bar 显示 model + open-app（最小闭环） | ✅   |
| **v2** | + L2 第三方 env | env 解析、hook 接入、多会话、窗口激活       | ✅   |
| **v3** | + L3 cc switch  | 完整 SQLite 读取、provider 切换、cost 数据  | 🟡 部分（cost 已读，切换 / popover / 分析待做） |

详见 [../ROUTES_MAP.md](../ROUTES_MAP.md)。
