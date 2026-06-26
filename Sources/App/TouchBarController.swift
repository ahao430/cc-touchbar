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
    private var modelLabel: NSTextField?
    private var balanceLabel: NSTextField?
    private var itemViews: [NSView] = []
    private var iconButtons: [NSButton] = []

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
            _ = state.activeSource
            _ = state.channelBalanceText
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
        bar.customizationIdentifier = "cc-touchbar.main.v3"
        bar.customizationAllowedItemIdentifiers = identifiers()
        self.touchBar = bar
        return bar
    }

    /// 在 place 更新各 item 的 view（不重建 NSTouchBar，不 dismiss/re-present）
    private func updateAllItems() {
        if providerButton?.attributedTitle.string != (state?.providerName ?? "—") {
            refreshProviderTitle()
        }
        modelLabel?.stringValue = state?.defaultModel ?? "—"
        balanceLabel?.stringValue = balanceText
    }

    private func identifiers() -> [NSTouchBarItem.Identifier] {
        return [.provider, .model, .balance, .openApp, .openCCSwitch, .collapse]
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case .provider:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(title: state?.providerName ?? "—", target: nil, action: nil)
            button.lineBreakMode = .byTruncatingTail
            button.cell?.truncatesLastVisibleLine = true
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            self.providerButton = button
            item.view = button
            registerItem(view: button)
            applyProviderTheme(button: button)
            return item

        case .model:
            let item = NSCustomTouchBarItem(identifier: id)
            let label = NSTextField(labelWithString: state?.defaultModel ?? "—")
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            self.modelLabel = label
            item.view = label
            registerItem(view: label)
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

        case .openApp:
            let item = NSCustomTouchBarItem(identifier: id)
            let image = appIconImage()
            let button = NSButton(image: image,
                                  target: self,
                                  action: #selector(openApp))
            item.view = button
            registerIcon(button: button)
            return item

        case .openCCSwitch:
            let item = NSCustomTouchBarItem(identifier: id)
            let image = ccSwitchIcon()
            let button = NSButton(image: image,
                                  target: self,
                                  action: #selector(openCCSwitch))
            item.view = button
            registerIcon(button: button)
            return item

        case .collapse:
            let item = NSCustomTouchBarItem(identifier: id)
            let button = NSButton(image: NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: "Collapse")!,
                                  target: self,
                                  action: #selector(collapseTouchBar))
            item.view = button
            registerIcon(button: button)
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

    // MARK: - Theme

    /// 主题切换：重新 apply 颜色到所有缓存的 item view
    func applyTheme(_ theme: Theme) {
        self.theme = theme
        itemViews.forEach { applyTheme(toItemView: $0) }
        iconButtons.forEach { applyTheme(toIconButton: $0) }
        if let provider = providerButton {
            applyProviderTheme(button: provider)
        }
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

    private var balanceText: String {
        state?.channelBalanceText ?? "余额 —"
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
    static let balance      = NSTouchBarItem.Identifier("cc-touchbar.balance")
    static let openApp      = NSTouchBarItem.Identifier("cc-touchbar.openApp")
    static let openCCSwitch = NSTouchBarItem.Identifier("cc-touchbar.openCCSwitch")
    static let collapse     = NSTouchBarItem.Identifier("cc-touchbar.collapse")
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("cc-touchbar.openMainWindow")
}
