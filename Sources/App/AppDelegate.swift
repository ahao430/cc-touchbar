import AppKit
import Observation

@Observable
final class AppState {
    var setupComplete: Bool = false
    var lastError: String?

    var claudeBinaryPath: String?
    var claudeBinaryIsNvmManaged: Bool = false
    var claudeConfigDir: URL?

    var activeSource: ActiveSource = .official

    var providerName: String = "—"
    var defaultModel: String = "—"

    var channelBalanceText: String = "余额 —"

    var contextUsedTokens: Int?
    var contextLimitTokens: Int?
    var contextModelName: String?

    /// 当前 session 累计 billed tokens（账单口径）
    var sessionBilledTokens: Int?
    /// 当前 session assistant message 数
    var sessionAssistantTurns: Int?
    /// 最近一条 assistant message 的 cache 命中率（0~1）
    var cacheHitRate: Double?

    var gitBranch: String?

    var thinkingBudgetTokens: Int?

    var touchBarSupported: Bool = false
    var bootDiagnostics: [String] = []
}

enum ActiveSource: Equatable {
    case official
    case envVars(baseURL: String)
    case ccSwitch
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()
    let sessions = SessionStore()
    let bridge = CCSwitchBridge()

    private var touchBarController: TouchBarController?
    private var mainWindowController: MainWindowController?
    private var ingester: HookIngester?
    private var transcriptWatcher: TranscriptWatcher?
    private var poller = Poller()
    private var balanceRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runBootDiagnostics()

        guard state.touchBarSupported else {
            presentUnsupportedModelAlert()
            NSApp.terminate(nil)
            return
        }

        // 1. 启动 hook ingester（永远起，未安装也会等文件）
        let ing = HookIngester()
        ing.attach(to: sessions)
        ingester = ing

        // 1.5 启动 transcript watcher（解析上下文用量）
        let tw = TranscriptWatcher()
        tw.attach(to: sessions, state: state)
        transcriptWatcher = tw

        // 2. 启动 settings.json 监听
        startSettingsPoller()

        // 3. cc switch 桥接（如果存在）
        bridge.onReload = { [weak self] in
            self?.reloadSource()
        }
        bridge.reload()

        // 3.5. 周期刷新余额（30s 一次，捕捉 cc-switch 写库后的变化）
        balanceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bridge.reload() }
        }

        // 4. 主窗口
        let wc = MainWindowController(state: state, sessions: sessions, bridge: bridge)
        wc.onPathsChanged = { [weak self] in
            self?.reapplyPaths()
        }
        wc.onThemeChanged = { [weak self] in
            self?.applyTheme()
        }
        wc.onRestartTouchBar = { [weak self] in
            self?.restartTouchBar()
        }
        mainWindowController = wc

        // 5. Touch Bar（DFR 系统级占用）
        let tc = TouchBarController()
        tc.bind(to: state, sessions: sessions, bridge: bridge, useDFR: true)
        touchBarController = tc

        // 6. 监听 NSWorkspace 焦点变化 → T1
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // 7. 监听 openMainWindow 通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: .openMainWindow,
            object: nil
        )

        // 启动时打开主窗口
        setupMainMenu()
        showMainWindow()
    }

    // MARK: - Main menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = "cc-touchbar"
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 cc-touchbar", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(withTitle: "隐藏 cc-touchbar", action: #selector(NSApp.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApp.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "退出 cc-touchbar", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "cc-touchbar"
        alert.informativeText = """
            版本 \(UpdateChecker.currentVersion)

            Touch Bar 实时显示 Claude Code 会话状态、上下文用量、渠道与余额。

            GitHub: github.com/ahao430/cc-touchbar
            """
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "前往 GitHub")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(UpdateChecker.repositoryURL)
        }
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check { [weak self] result in
            self?.presentUpdateResult(result)
        }
    }

    private func presentUpdateResult(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch result {
        case .upToDate(let current):
            alert.messageText = "已是最新版本"
            alert.informativeText = "当前版本 \(current)"
            alert.addButton(withTitle: "关闭")
        case .newVersionAvailable(let current, let latest, let url):
            alert.messageText = "发现新版本 \(latest)"
            alert.informativeText = "当前版本 \(current)，新版本 \(latest) 已发布。\n是否立即前往下载？"
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
            return
        case .error(let msg):
            alert.messageText = "检查更新失败"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "关闭")
        }
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if mainWindowController?.window?.isVisible != true {
            showMainWindow()
        }
    }

    // MARK: - Boot diagnostics

    private func runBootDiagnostics() {
        state.bootDiagnostics.removeAll()

        if TouchBarMachineDetector.isTouchBarSupported() {
            state.touchBarSupported = true
            state.bootDiagnostics.append("✔ Touch Bar: \(TouchBarMachineDetector.modelIdentifier() ?? "unknown")")
        } else {
            state.touchBarSupported = false
            state.bootDiagnostics.append("✖ Touch Bar: 不支持的机型")
        }

        let claude = ClaudeDetector.resolvedBinary()
        if let path = claude.path {
            state.claudeBinaryPath = path
            state.claudeBinaryIsNvmManaged = path.contains("/.nvm/")
            state.bootDiagnostics.append("✔ Claude Code [\(claude.source.rawValue)]: \(path)")
        } else {
            state.bootDiagnostics.append("✖ Claude Code: \(claude.source.rawValue)")
        }

        state.claudeConfigDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        reloadSource()

        // hook 状态
        let dispatcherOK = HookScript.isInstalled
        let settingsOK = HookInstaller.isRegisteredInSettings()
        state.bootDiagnostics.append("✔ dispatcher: \(dispatcherOK ? "已安装" : "未安装")")
        state.bootDiagnostics.append("✔ settings.json hook: \(settingsOK ? "已注册" : "未注册")")
        if dispatcherOK && settingsOK {
            PreferenceStore.shared.hooksInstalled = true
        }

        // cc switch
        let cc = AppPathsResolver.resolvedCCSwitchDB()
        if let url = cc.url {
            state.bootDiagnostics.append("✔ cc switch [\(cc.source.rawValue)]: \(url.path)")
        } else {
            state.bootDiagnostics.append("• cc switch: \(cc.source.rawValue)（L3 不可用，不影响 L1/L2）")
        }

        state.setupComplete = state.touchBarSupported && state.claudeBinaryPath != nil
    }

    /// 路径覆盖变化后重新跑诊断 + 刷 HUD
    func reapplyPaths() {
        runBootDiagnostics()
        bridge.reload()
    }

    /// 主题变化后把新主题推到 Touch Bar
    func applyTheme() {
        touchBarController?.applyTheme(Theme.current())
    }

    /// 重启 Touch Bar
    func restartTouchBar() {
        touchBarController?.restart()
    }

    private func reloadSource() {
        guard let configDir = state.claudeConfigDir else { return }
        if let settings = try? SettingsJsonReader.read(at: configDir) {
            let resolved = SourceResolver.resolve(
                settings: settings,
                ccSwitchDBPresent: bridge.isAvailable,
                ccSwitchActiveName: bridge.activeProvider?.name
            )
            let providerChanged = state.providerName != resolved.providerName
            state.activeSource = resolved.source
            state.providerName = resolved.providerName
            state.defaultModel = resolved.defaultModel
            if providerChanged { state.contextModelName = nil }

            if let raw = settings.env?.maxThinkingTokens,
               let v = Int(raw), v > 0 {
                state.thinkingBudgetTokens = v
            } else {
                state.thinkingBudgetTokens = nil
            }
        }
        state.channelBalanceText = bridge.balanceText
    }

    private func startSettingsPoller() {
        guard let configDir = state.claudeConfigDir else { return }
        let settingsURL = configDir.appendingPathComponent("settings.json")
        poller.watch(settingsURL) { [weak self] in
            Task { @MainActor in
                self?.reloadSource()
            }
        }
    }

    @objc private func appDidActivate(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            sessions.setFocusedApp(pid: app.processIdentifier)
        }
        // 切窗口立刻刷一遍渠道 / 余额，不等 30s 定时器
        bridge.reload()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(self)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func presentUnsupportedModelAlert() {
        let alert = NSAlert()
        alert.messageText = "不支持的机型"
        alert.informativeText = """
            cc-touchbar 仅支持带 Touch Bar 的 MacBook：
            • MacBook Pro 2016–2019 (Intel)
            • MacBook Pro 2020 (M1, 13-inch)

            检测到机型：\(TouchBarMachineDetector.modelIdentifier() ?? "未知")
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        alert.runModal()
    }
}
