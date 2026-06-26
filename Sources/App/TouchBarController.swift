import AppKit
import Observation

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {

    private weak var state: AppState?
    private weak var sessions: SessionStore?
    private weak var bridge: CCSwitchBridge?
    private var touchBar: NSTouchBar?

    // 持有各 item 的 view 引用，状态变化时直接更新 view，不重建 NSTouchBar
    private var providerButton: NSButton?
    private var modelLabel: NSButton?
    private var balanceLabel: NSTextField?
    private var contextLabel: NSTextField?
    private var costLabel: NSTextField?
    private var thinkingLabel: NSTextField?
    private var gitBranchLabel: NSButton?
    private var itemViews: [NSView] = []
    private var iconButtons: [NSButton] = []
    private var separatorViews: [NSView] = []

    // 宽度切换：点击 provider/model/gitBranch 在自适应和固定宽度之间切换
    private var providerAutoWidth: NSLayoutConstraint?
    private var providerFixedWidth: NSLayoutConstraint?
    private var providerWidthIsFixed = true
    private var modelAutoMaxWidth: NSLayoutConstraint?
    private var modelAutoMinWidth: NSLayoutConstraint?
    private var modelFixedWidth: NSLayoutConstraint?
    private var modelWidthIsFixed = true
    private var gitBranchAutoMaxWidth: NSLayoutConstraint?
    private var gitBranchAutoMinWidth: NSLayoutConstraint?
    private var gitBranchFixedWidth: NSLayoutConstraint?
    private var gitBranchWidthIsFixed = true

    private var observerActive = false
    private var dfrEnabled = false
    private var theme: Theme = .dark

    func bind(to state: AppState, sessions: SessionStore, bridge: CCSwitchBridge, useDFR: Bool = true) {
        self.state = state
        self.sessions = sessions
        self.bridge = bridge
        self.dfrEnabled = useDFR
        self.theme = Theme.current()

        // 先创建 + present（仅一次），再开始观察
        if useDFR {
            SystemTouchBarPresenter.setupTrayItem(target: self,
                                                  action: #selector(reopenFromTray),
                                                  image: nil)
            presentDFR()
        } else {
            NSApp.touchBar = makeTouchBar()
        }
        startObservation()
    }

    private func presentDFR() {
        Task { @MainActor [weak self] in
            guard let self,
                  let bar = self.makeTouchBar() else { return }
            SystemTouchBarPresenter.present(bar)
        }
    }

    /// 用户点 Control Strip 里的 tray icon 触发：重新展开 HUD
    @objc private func reopenFromTray() {
        presentDFR()
    }

    func dismissDFR() {
        SystemTouchBarPresenter.dismiss()
    }

    func minimizeDFR() {
        SystemTouchBarPresenter.minimize()
    }

    private func startObservation() {
        guard !observerActive else { return }
        observerActive = true
        observeChanges()
    }

    /// 递归重订阅 —— 状态变化只 update view 内容，不重建 NSTouchBar
    private func observeChanges() {
        guard let state, let sessions else { return }
        Observation.withObservationTracking {
            _ = state.providerName
            _ = state.defaultModel
            _ = state.contextModelName
            _ = state.activeSource
            _ = state.channelBalanceText
            _ = state.contextUsedTokens
            _ = state.contextLimitTokens
            _ = state.sessionBilledTokens
            _ = state.cacheHitRate
            _ = state.thinkingBudgetTokens
            _ = state.gitBranch
            _ = sessions.focusedAppPID
            _ = sessions.lastHookActiveSessionID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateAllItems()
                self?.observeChanges()
            }
        }
    }

    func makeTouchBar() -> NSTouchBar? {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = identifiers()
        bar.customizationIdentifier = nil
        bar.customizationAllowedItemIdentifiers = []
        self.touchBar = bar
        return bar
    }

    /// 在 place 更新各 item 的 view（不重建 NSTouchBar，不 dismiss/re-present）
    private func updateAllItems() {
        if providerButton?.attributedTitle.string != (state?.providerName ?? "—") {
            refreshProviderTitle()
        }
        providerButton?.toolTip = state?.providerName ?? "—"
        if modelLabel?.title != modelText {
            refreshModelTitle()
        }
        balanceLabel?.stringValue = balanceText
        contextLabel?.stringValue = contextText
        contextLabel?.toolTip = contextTooltip
        costLabel?.stringValue = costText
        costLabel?.toolTip = costTooltip
        thinkingLabel?.stringValue = thinkingText
        thinkingLabel?.toolTip = thinkingTooltip
        if gitBranchLabel?.title != gitBranchText {
            refreshGitBranchTitle()
        }
        gitBranchLabel?.toolTip = gitBranchTooltip
    }

    private func identifiers() -> [NSTouchBarItem.Identifier] {
        return [.provider, .model, .sep1, .balance, .sep2, .context, .cost, .thinking, .sep3, .gitBranch, .openApp, .openCCSwitch, .collapse]
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case .provider:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(title: state?.providerName ?? "—", target: self, action: #selector(toggleProviderWidth))
            button.lineBreakMode = .byTruncatingTail
            button.cell?.truncatesLastVisibleLine = true
            button.cell?.wraps = false
            button.translatesAutoresizingMaskIntoConstraints = false
            let autoC = button.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
            autoC.isActive = false
            providerAutoWidth = autoC
            let fixedC = button.widthAnchor.constraint(equalToConstant: 80)
            fixedC.isActive = true
            providerFixedWidth = fixedC
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.toolTip = state?.providerName ?? "—"
            self.providerButton = button
            item.view = button
            registerItem(view: button)
            applyProviderTheme(button: button)
            return item

        case .model:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(title: modelText, target: self, action: #selector(toggleModelWidth))
            button.isBordered = false
            button.bezelStyle = .inline
            button.alignment = .center
            button.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            button.lineBreakMode = .byTruncatingTail
            button.cell?.wraps = false
            button.cell?.truncatesLastVisibleLine = true
            button.translatesAutoresizingMaskIntoConstraints = false
            let maxC = button.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
            let minC = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
            maxC.isActive = false
            minC.isActive = false
            modelAutoMaxWidth = maxC
            modelAutoMinWidth = minC
            let fixedC = button.widthAnchor.constraint(equalToConstant: 80)
            fixedC.isActive = true
            modelFixedWidth = fixedC
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.modelLabel = button
            item.view = button
            registerItem(view: button)
            refreshModelTitle()
            return item

        case .balance:
            let item = NSCustomTouchBarItem(identifier: id)
            let label = NSTextField(labelWithString: balanceText)
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.toolTip = "当前渠道余额"
            self.balanceLabel = label
            item.view = label
            registerItem(view: label)
            return item

        case .context:
            let item = NSCustomTouchBarItem(identifier: id)
            let label = NSTextField(labelWithString: contextText)
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.toolTip = contextTooltip
            self.contextLabel = label
            item.view = label
            registerItem(view: label)
            return item

        case .cost:
            let item = NSCustomTouchBarItem(identifier: id)
            let label = NSTextField(labelWithString: costText)
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.toolTip = costTooltip
            self.costLabel = label
            item.view = label
            registerItem(view: label)
            return item

        case .thinking:
            let item = NSCustomTouchBarItem(identifier: id)
            let label = NSTextField(labelWithString: thinkingText)
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.toolTip = thinkingTooltip
            self.thinkingLabel = label
            item.view = label
            registerItem(view: label)
            return item

        case .openApp:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(image: appIconImage(),
                                  target: self,
                                  action: #selector(openApp))
            configureIconButton(button)
            item.view = button
            registerIcon(button: button)
            return item

        case .openCCSwitch:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(image: ccSwitchIcon(),
                                  target: self,
                                  action: #selector(openCCSwitch))
            configureIconButton(button)
            item.view = button
            registerIcon(button: button)
            return item

        case .collapse:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(image: NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: "Collapse")!,
                                  target: self,
                                  action: #selector(collapseTouchBar))
            configureIconButton(button)
            item.view = button
            registerIcon(button: button)
            return item

        case .sep1, .sep2, .sep3:
            let item = NSCustomTouchBarItem(identifier: id)
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = theme.separatorColor.cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            line.widthAnchor.constraint(equalToConstant: 1.5).isActive = true
            line.heightAnchor.constraint(equalToConstant: 22).isActive = true
            item.view = line
            separatorViews.append(line)
            return item

        case .gitBranch:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(title: gitBranchText, target: self, action: #selector(toggleGitBranchWidth))
            button.isBordered = false
            button.bezelStyle = .inline
            button.alignment = .center
            button.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            button.toolTip = gitBranchTooltip
            button.lineBreakMode = .byTruncatingTail
            button.cell?.wraps = false
            button.cell?.truncatesLastVisibleLine = true
            button.translatesAutoresizingMaskIntoConstraints = false
            let maxC = button.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
            let minC = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
            maxC.isActive = false
            minC.isActive = false
            gitBranchAutoMaxWidth = maxC
            gitBranchAutoMinWidth = minC
            let fixedC = button.widthAnchor.constraint(equalToConstant: 80)
            fixedC.isActive = true
            gitBranchFixedWidth = fixedC
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.gitBranchLabel = button
            item.view = button
            registerItem(view: button)
            refreshGitBranchTitle()
            return item

        default:
            return nil
        }
    }

    private func registerItem(view: NSView) {
        itemViews.append(view)
        applyTheme(toItemView: view)
    }

    private func registerIcon(button: NSButton) {
        iconButtons.append(button)
        applyTheme(toIconButton: button)
    }

    /// 图标按钮统一压缩：inline bezel + 紧凑宽度
    private func configureIconButton(_ button: NSButton) {
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    // MARK: - Theme

    /// 主题切换：重新 apply 颜色到所有缓存的 item view
    func applyTheme(_ theme: Theme) {
        self.theme = theme
        itemViews.forEach { applyTheme(toItemView: $0) }
        iconButtons.forEach { applyTheme(toIconButton: $0) }
        separatorViews.forEach { $0.layer?.backgroundColor = theme.separatorColor.cgColor }
        if let provider = providerButton {
            applyProviderTheme(button: provider)
        }
        refreshModelTitle()
        refreshGitBranchTitle()
    }

    private func applyTheme(toItemView view: NSView) {
        // item 背景（仅浅色主题会画一层底色）
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.itemBackground?.cgColor
        view.layer?.cornerRadius = 6

        if let label = view as? NSTextField {
            label.textColor = theme.secondaryText
        }
    }

    private func applyTheme(toIconButton button: NSButton) {
        // 图标按钮 bezel 用主题 accent 的低透明度
        button.bezelColor = theme.accent.withAlphaComponent(0.25)
        button.contentTintColor = theme.primaryText
        button.wantsLayer = true
        button.layer?.backgroundColor = theme.itemBackground?.cgColor
        button.layer?.cornerRadius = 6
    }

    private func applyProviderTheme(button: NSButton) {
        button.bezelColor = theme.providerBezel
        // 强制供应商文字用主题 providerText（默认白），保证在彩色 bezel 上读得清
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.providerText,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .semibold)
        ]
        let title = button.title
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    // 供应商 title 改变后调用，保留主题文字颜色
    private func refreshProviderTitle() {
        guard let button = providerButton else { return }
        let title = state?.providerName ?? "—"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.providerText,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .semibold)
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    private var modelText: String {
        let raw = state?.contextModelName ?? state?.defaultModel ?? ""
        return raw.isEmpty ? "—" : raw
    }

    private func refreshModelTitle() {
        guard let button = modelLabel else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.secondaryText,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        button.attributedTitle = NSAttributedString(string: modelText, attributes: attrs)
    }

    private func refreshGitBranchTitle() {
        guard let button = gitBranchLabel else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.secondaryText,
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]
        button.attributedTitle = NSAttributedString(string: gitBranchText, attributes: attrs)
    }

    @objc private func toggleProviderWidth() {
        providerWidthIsFixed.toggle()
        providerAutoWidth?.isActive = !providerWidthIsFixed
        providerFixedWidth?.isActive = providerWidthIsFixed
        providerButton?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleModelWidth() {
        modelWidthIsFixed.toggle()
        modelAutoMaxWidth?.isActive = !modelWidthIsFixed
        modelAutoMinWidth?.isActive = !modelWidthIsFixed
        modelFixedWidth?.isActive = modelWidthIsFixed
        modelLabel?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleGitBranchWidth() {
        gitBranchWidthIsFixed.toggle()
        gitBranchAutoMaxWidth?.isActive = !gitBranchWidthIsFixed
        gitBranchAutoMinWidth?.isActive = !gitBranchWidthIsFixed
        gitBranchFixedWidth?.isActive = gitBranchWidthIsFixed
        gitBranchLabel?.layoutSubtreeIfNeeded()
    }

    private var balanceText: String {
        state?.channelBalanceText ?? "余额 —"
    }

    /// 上下文使用：`ctx 78%` 或 `ctx —`；接近 80%/95% 时附 warning 角标
    private var contextText: String {
        guard let used = state?.contextUsedTokens,
              let limit = state?.contextLimitTokens,
              limit > 0 else {
            return "ctx —"
        }
        let pct = min(999, Int(Double(used) / Double(limit) * 100))
        if pct >= 95 { return "ctx ‼︎\(pct)%" }
        if pct >= 80 { return "ctx ⚠︎\(pct)%" }
        return "ctx \(pct)%"
    }

    private var contextTooltip: String {
        guard let used = state?.contextUsedTokens,
              let limit = state?.contextLimitTokens else {
            return "上下文用量（无 transcript）"
        }
        let model = state?.contextModelName ?? "—"
        return "上下文：\(formatTokens(used)) / \(formatTokens(limit))\n模型：\(model)"
    }

    /// Session 累计 billed tokens（账单口径：input + creation×1.25 + read×0.1 + output）
    /// + 最近一条 message 的 cache 命中率
    private var costText: String {
        guard let billed = state?.sessionBilledTokens, billed > 0 else {
            return "Σ —"
        }
        if let rate = state?.cacheHitRate {
            let pct = Int((rate * 100).rounded())
            return "Σ \(formatTokens(billed)) ⚡\(pct)%"
        }
        return "Σ \(formatTokens(billed))"
    }

    private var costTooltip: String {
        guard let billed = state?.sessionBilledTokens, billed > 0 else {
            return "本 session 累计 billed tokens（无 transcript）"
        }
        let turns = state?.sessionAssistantTurns ?? 0
        var lines = [
            "本 session 累计：\(formatTokens(billed)) tokens",
            "账单口径：input + creation×1.25 + read×0.1 + output",
            "轮数：\(turns)"
        ]
        if let rate = state?.cacheHitRate {
            let pct = Int((rate * 100).rounded())
            lines.append("Cache 命中率（最近一轮）：\(pct)%")
        }
        return lines.joined(separator: "\n")
    }

    /// Thinking 预算：MAX_THINKING_TOKENS 未设置则不显示数字
    private var thinkingText: String {
        guard let budget = state?.thinkingBudgetTokens, budget > 0 else {
            return ""
        }
        return "💭 \(formatTokens(budget))"
    }

    private var thinkingTooltip: String {
        guard let budget = state?.thinkingBudgetTokens, budget > 0 else {
            return "MAX_THINKING_TOKENS 未设置"
        }
        let tier: String
        switch budget {
        case 1...3999: tier = "think"
        case 4000...10000: tier = "megathink"
        case 10001...31998: tier = "think harder"
        default: tier = "ultrathink"
        }
        return "MAX_THINKING_TOKENS = \(budget)\n档位：\(tier)"
    }

    private var gitBranchText: String {
        guard let branch = state?.gitBranch, !branch.isEmpty else {
            return "⎇ —"
        }
        return "⎇ \(branch)"
    }

    private var gitBranchTooltip: String {
        guard let branch = state?.gitBranch, !branch.isEmpty else {
            return "当前目录无 git 仓库"
        }
        return "git: \(branch)"
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return String(format: "%.1fM", v)
        }
        if n >= 1000 {
            return "\(Int(round(Double(n) / 1000)))k"
        }
        return "\(n)"
    }

    /// cc-touchbar 自身图标 —— 与 Control Strip tray 同源（bundle 里的 logo.png）
    private func appIconImage() -> NSImage {
        let bundled: NSImage? = {
            if let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
                return NSImage(contentsOf: url)
            }
            if let url = Bundle.main.url(forResource: "ClaudeIcon", withExtension: "png") {
                return NSImage(contentsOf: url)
            }
            return nil
        }()
        if let img = bundled {
            img.isTemplate = false
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "app.badge", accessibilityDescription: "cc-touchbar")!
    }

    /// CC Switch 应用图标 —— 直接从 /Applications/CC Switch.app 取
    private func ccSwitchIcon() -> NSImage {
        let path = "/Applications/CC Switch.app"
        if FileManager.default.fileExists(atPath: path) {
            let img = NSWorkspace.shared.icon(forFile: path)
            img.isTemplate = false
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "CC Switch")!
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @objc private func openCCSwitch() {
        let path = "/Applications/CC Switch.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    @objc private func collapseTouchBar() {
        minimizeDFR()
    }
}

extension NSTouchBarItem.Identifier {
    static let provider     = NSTouchBarItem.Identifier("cc-touchbar.provider")
    static let model        = NSTouchBarItem.Identifier("cc-touchbar.model")
    static let sep1         = NSTouchBarItem.Identifier("cc-touchbar.sep1")
    static let balance      = NSTouchBarItem.Identifier("cc-touchbar.balance")
    static let sep2         = NSTouchBarItem.Identifier("cc-touchbar.sep2")
    static let context      = NSTouchBarItem.Identifier("cc-touchbar.context")
    static let cost         = NSTouchBarItem.Identifier("cc-touchbar.cost")
    static let thinking     = NSTouchBarItem.Identifier("cc-touchbar.thinking")
    static let sep3         = NSTouchBarItem.Identifier("cc-touchbar.sep3")
    static let gitBranch    = NSTouchBarItem.Identifier("cc-touchbar.gitBranch")
    static let openApp      = NSTouchBarItem.Identifier("cc-touchbar.openApp")
    static let openCCSwitch = NSTouchBarItem.Identifier("cc-touchbar.openCCSwitch")
    static let collapse     = NSTouchBarItem.Identifier("cc-touchbar.collapse")
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("cc-touchbar.openMainWindow")
}
