# 路线图（Roadmap）

> 当前实现状态 + TODO。
>
> 状态图例：✅ 已完成 · 🟡 部分完成 · 🔲 TODO · ❌ 已放弃（含原因）

## v1 — 官方订阅 + Touch Bar 基础 ✅

| 项 | 状态 | 备注 |
|---|---|---|
| Xcode 工程（DEBUG 签名、`LSUIElement = NO`） | ✅ | |
| 机型检测（启动时校验，不支持退出） | ✅ | `TouchBarMachineDetector` |
| `AppState` / `PreferenceStore` | ✅ | 用 Swift Observation |
| `ClaudeDetector`（登录 shell `which claude` + nvm 兜底 + 手动覆盖） | ✅ | |
| `SettingsJsonReader` | ✅ | |
| `SourceResolver`（L1/L2/L3 推断） | ✅ | |
| `TouchBarController` 显示 `[ provider ] [ model ] [ ⚙ ]` | ✅ | |
| `Poller` 监听 `settings.json` 变化 | ✅ | |
| App 主窗口（替代 Setup Wizard，直接展示状态 + 诊断） | ✅ | 决策变更：不做 Wizard，所有"重新检测"在主窗口 footer |

## v2 — 第三方 env + Hook + 多会话 ✅

| 项 | 状态 | 备注 |
|---|---|---|
| Hook 脚本（`HookScript`）+ 自动安装到 `~/.claude/cc-touchbar-dispatcher.sh` | ✅ | |
| `HookInstaller`：合并 `settings.json` hooks 块（用户已有 hooks 不覆盖） | ✅ | |
| `HookIngester`：FSEvents 监听 JSONL、按行解析 | ✅ | |
| `SessionStore`：sessions 字典 + 生命周期 / cwd / hostApp | ✅ | |
| 主窗口会话列表 | ✅ | |
| `WindowActivator`：iTerm + Terminal.app + tmux | ✅ | |
| Provider 友好名映射（L2） | ✅ | cc switch 走 `name`；L2 fallback 到 hostname |
| Trigger 2：活动时间戳决定 focused session | ✅ | |
| Trigger 1：NSWorkspace 焦点联动 | ✅ | 切窗口立即刷 bridge |
| **Touch Bar 状态文字字段（status）** | 🔲 | 当前只用动画 status icon，没文字字段 |
| **Touch Bar cwd 字段** | 🔲 | 列表里有；HUD 暂未加 |
| **Touch Bar 会话计时（duration）** | ❌ 已移除 | 决策变更：价值低，节省 Touch Bar 空间 |
| **`StatusIconView` 动画（thinking / streaming / error）** | 🟡 | view 存在，动画细节 TODO |
| CwdChanged / ConfigChange hook 处理 | ✅ | |

## v3 — cc switch 集成 🟡

| 项 | 状态 | 备注 |
|---|---|---|
| **cc switch SQLite 读取** | ✅ | activeProvider / providers / 余额（含 Zhipu `nextResetTime`） |
| **DFR（系统模态 Touch Bar + Control Strip tray）** | ✅ | 决策变更：从 v3 后期提前到 v2 末期，因为没有它切到其它 app HUD 就消失了 |
| **openCCS**：唤起 cc switch GUI | ✅ | |
| **余额显示**：周期 + 百分比 + 刷新剩余时间 | ✅ | Zhipu 专属，通过 `/api/monitor/usage/quota/limit` |
| **HUD：上下文用量** | ✅ | 0.0.2：`TranscriptWatcher` tail transcript，`ctx 78%` |
| **HUD：累计 billed tokens** | ✅ | 0.0.2：账单口径累加，`Σ 1.2M ⚡92%` |
| **HUD：cache 命中率** | ✅ | 0.0.2：最近一轮 `cache_read / total_input` |
| **HUD：thinking 预算** | ✅ | 0.0.2：从 env `MAX_THINKING_TOKENS` 读，未设置则空白 |
| **HUD：分隔线 / 按钮收紧 / 供应商宽度** | ✅ | 0.0.2：1.5pt 竖线 + inline bezel + 130pt 上限 |
| **provider popover + 健康状态**（Touch Bar + 主窗口） | 🔲 | |
| **直写 SQLite 切 provider** | 🔲 | 需先逆向 cc-switch reload 机制 |
| **完整跨终端激活**：Ghostty / WezTerm / VS Code URL scheme | 🔲 | 当前用 PID fallback |
| **远程 session 检测**（CC 在 SSH 远端） | 🔲 | |
| **多 app_type**：codex / gemini | 🔲 | |
| **使用分析图表**（按 provider / 模型拆分） | 🔲 | |
| **post-MVP hook 利用**：`PostToolUse` token、`PostToolBatch` | 🟡 | 0.0.2：transcript JSONL 已解析（usage / cache）；PostToolUse payload 本身的 token 字段未用 |
| **cc switch deeplink**：`openUI(toProvider:)` | 🔲 | 需先确认 Tauri 是否暴露 |
| **HUD：活跃 session 计数 / cwd 字段** | 🔲 | 数据现成，加 item 即可（ROUTES 待定） |
| **HUD：估算 USD 花费** | 🔲 | 需维护各家供应商价格表 |

## 主题系统 🟡

> 详见 [11-主题系统.md](11-主题系统.md)。

| 项 | 状态 | 备注 |
|---|---|---|
| 主题基础设施（`Theme` struct + `PreferenceStore.themeName`） | ✅ | |
| 深色主题（默认） | ✅ | |
| 浅色主题（item 加白底） | ✅ | |
| 主窗口主题切换面板 | ✅ | |
| **Cyberpunk 主题** | 🔲 | |
| **Pastel Dream 主题** | 🔲 | |
| **Terminal Green 主题** | 🔲 | |
| **自定义主题面板**（颜色 / 字体 / 图标） | 🔲 | |
| **导入导出 JSON** | 🔲 | |
| **图标 tint / glow**（streaming 时发光） | 🔲 | |
| **字体配置**（JetBrains Mono / Menlo 等） | 🔲 | |

## 工程化与体验

| 项 | 状态 | 备注 |
|---|---|---|
| 路径手动覆盖（Claude binary / cc switch DB） | ✅ | `PreferenceStore` + 主窗口「路径…」按钮 |
| 诊断面板（启动时收集） | ✅ | 机型 / 路径 / source / hook 状态 |
| 30s 余额刷新定时器 | ✅ | 捕捉 cc-switch 写库后的变化 |
| **日志文件**（`~/Library/Logs/cc-touchbar/`） | 🔲 | 当前只有 `/tmp/cc-touchbar-dfr.log` |
| **「复制诊断信息」按钮** | 🔲 | |
| **会话右键菜单**（Copy cwd / Open in Finder / Open in Terminal / Show in cc switch / End session） | 🔲 | |
| **jsonl 文件 GC**（7 天前清理） | 🔲 | |
| **开机自启** | 🔲 | |
| **Sparkle / 自更新** | 🔲 | |

## 构建顺序回顾（实际走过的）

```
v1 ─────────
1. 机型检测 + AppDelegate                       ✔
2. ClaudeDetector（登录 shell which + nvm 兜底） ✔
3. SettingsJsonReader + SourceResolver          ✔
4. TouchBarController 骨架（provider + openApp） ✔
5. Poller（监听 settings.json）                 ✔
6. 主窗口（替代 Setup Wizard）                   ✔

v2 ─────────
7. HookScript + HookInstaller                   ✔
8. HookIngester + SessionStore                  ✔
9. 主窗口会话列表                                ✔
10. WindowActivator（iTerm + Terminal + tmux）  ✔
11. Trigger 2（活动时间戳）                      ✔
12. Trigger 1（NSWorkspace + 立即刷 bridge）     ✔
13. provider 友好名映射                          ✔

v3（提前 / 进行中）─────
14. CCSwitchBridge SQLite 只读                   ✔
15. DFR（系统模态 + Control Strip tray）         ✔   ← 从 v3 后期提前
16. openCCS + collapse 按钮                      ✔
17. Zhipu `nextResetTime` 余额剩余时间           ✔
18. 路径手动覆盖                                  ✔
19. 主题系统（2 套预设 + 主窗口切换）              ✔
20. provider popover + 健康状态                  ⏳
21. reverse-engineer cc-switch reload           ⏳
22. Ghostty / WezTerm / VS Code 精细激活         ⏳
23. 多 app_type                                  ⏳
24. 使用分析图表                                  ⏳
25. 主题系统完整化（3 套 + 自定义 + 导入导出）     ⏳
```

## 上线前 checklist

- [ ] 在干净的 macOS（没装 cc switch / Claude Code）上跑过，确认降级路径
- [ ] 在装了 Claude Code 但**没装 cc switch** 的机器上完整跑过（验证 L1/L2 链路）
- [ ] 在装了 cc switch 但没启动的情况下跑过 App，确认错误处理
- [ ] hook 脚本 1000 次调用测试（性能 + 鲁棒性）
- [ ] 没有 Touch Bar 的设备启动 App，确认友好退出（不是崩溃）
- [ ] App 进入后台 1 小时后唤醒，状态恢复正确
- [ ] 内存占用稳定（连续运行 24 小时无明显增长）
- [ ] 用户从 L3（cc switch）手动切到 L2（env vars）时 HUD 正确响应

## 与原始计划（PLAN.md 旧版）的差异

旧版（已删除）默认 cc switch 是必须的、所有数据从 cc switch SQLite 读。当前版本：

1. **三层数据源**：官方订阅 / 第三方 env / cc switch，按层级递进
2. **cc switch 是可选增强**：装了用 L3，没装走 L1/L2
3. **MVP 顺序倒过来**：从最简单的 L1 开始，最复杂的 cc switch 放最后
4. **仅支持 Touch Bar 机型**：不兼容设备直接退出，不做 fallback
5. **不做 Setup Wizard**：所有"重新检测 / 手动覆盖"直接放在主窗口 footer
6. **DFR 提前**：原计划 v3 后期，实际在 v2 末期就接入了
7. **主题系统简化起步**：原计划一次做 5 套预设 + 自定义 + 导入导出，实际先打通 2 套 + 切换链路，完整版进路线图

## 路线图与发布的关系

| 版本 | 范围 | 状态 |
|---|---|---|
| `0.0.x` | v1 + v2 + v3 部分（DFR / 余额 / 路径覆盖 / 主题切换 / HUD 用量信息） | 当前 |
| `0.1.x` | v3 收尾：provider popover + 健康状态 + 跨终端完整激活 | 计划中 |
| `0.2.x` | 主题系统完整化（自定义 + 导入导出 + 剩余 3 套预设） | 计划中 |
| `0.3.x` | 直写 SQLite 切 provider（依赖 cc-switch reload 逆向） | 计划中 |
| `0.4.x` | 使用分析图表 + 多 app_type | 计划中 |

发布说明见 [RELEASES.md](RELEASES.md)。
