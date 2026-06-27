import AppKit
import Observation

private enum MainPanel { case sessions, settings }

@MainActor
final class MainWindowController: NSWindowController {

    private weak var state: AppState?
    private weak var sessions: SessionStore?
    private weak var bridge: CCSwitchBridge?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerView = NSStackView()
    private let footerView = NSStackView()
    private let settingsContainer = NSStackView()

    private var currentPanel: MainPanel = .sessions
    private var observerToken: Any?

    /// 路径覆盖变化后由 AppDelegate 重新跑诊断 + 刷 HUD
    var onPathsChanged: (() -> Void)?

    /// 主题切换后由 AppDelegate 把新主题推到 TouchBarController
    var onThemeChanged: (() -> Void)?

    /// 重启 Touch Bar（DFR dismiss + 重新 make + present）
    var onRestartTouchBar: (() -> Void)?

    init(state: AppState, sessions: SessionStore, bridge: CCSwitchBridge) {
        self.state = state
        self.sessions = sessions
        self.bridge = bridge

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "cc-touchbar"
        window.center()
        super.init(window: window)
        setupUI()
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Header
        headerView.orientation = .horizontal
        headerView.spacing = 12
        headerView.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Footer
        footerView.orientation = .horizontal
        footerView.spacing = 8
        footerView.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 12, right: 16)
        footerView.translatesAutoresizingMaskIntoConstraints = false

        // Table
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 44
        let col = NSTableColumn(identifier: .init("main"))
        tableView.addTableColumn(col)
        tableView.selectionHighlightStyle = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Settings panel
        settingsContainer.orientation = .vertical
        settingsContainer.alignment = .width
        settingsContainer.spacing = 18
        settingsContainer.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.isHidden = true

        contentView.addSubview(headerView)
        contentView.addSubview(scrollView)
        contentView.addSubview(settingsContainer)
        contentView.addSubview(footerView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            settingsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            settingsContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            settingsContainer.widthAnchor.constraint(equalToConstant: 600),
            settingsContainer.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window?.minSize = NSSize(width: 640, height: 400)

        rebuildHeader()
        rebuildSettings()
        rebuildFooter()
    }

    private func observe() {
        // 监听 sessions 变化刷新表
        let token = Observation.withObservationTracking {
            _ = sessions?.sessions
            _ = sessions?.focusedAppPID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.tableView.reloadData()
                self?.observe()
            }
        }
        observerToken = token
    }

    // MARK: - Header

    private func rebuildHeader() {
        headerView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch currentPanel {
        case .sessions:
            let title = NSTextField(labelWithString: "cc-touchbar")
            title.font = .systemFont(ofSize: 14, weight: .semibold)

            let provider = makeChip(label: state?.providerName ?? "—", color: .systemBlue)
            let model = makeChip(label: state?.defaultModel ?? "—", color: .systemPurple)
            let source = makeChip(label: sourceLabel, color: .systemGray)

            headerView.addArrangedSubview(title)
            headerView.addArrangedSubview(NSStackView.horizontalSpacer())
            headerView.addArrangedSubview(provider)
            headerView.addArrangedSubview(model)
            headerView.addArrangedSubview(source)
            headerView.addArrangedSubview(makeGitHubButton())
            headerView.addArrangedSubview(makeSettingsButton())

        case .settings:
            let backButton = NSButton(image: NSImage(systemSymbolName: "chevron.backward",
                                                      accessibilityDescription: "返回")!,
                                       target: self,
                                       action: #selector(showSessionsPanel))
            backButton.bezelStyle = .rounded
            backButton.imagePosition = .imageOnly

            let title = NSTextField(labelWithString: "设置")
            title.font = .systemFont(ofSize: 14, weight: .semibold)

            headerView.addArrangedSubview(backButton)
            headerView.addArrangedSubview(title)
            headerView.addArrangedSubview(NSStackView.horizontalSpacer())
        }
    }

    private func makeGitHubButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(openGitHub))
        button.bezelStyle = .rounded
        if let url = Bundle.main.url(forResource: "GitHubMark", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 16, height: 16)
            button.image = img
            button.imagePosition = .imageOnly
            button.contentTintColor = .labelColor
        } else {
            button.title = "GitHub"
        }
        button.toolTip = "GitHub 仓库"
        return button
    }

    private func makeSettingsButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(showSettingsPanel))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "gearshape",
                                accessibilityDescription: "设置")
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = "设置"
        return button
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(UpdateChecker.repositoryURL)
    }

    @objc private func showSessionsPanel() {
        currentPanel = .sessions
        scrollView.isHidden = false
        settingsContainer.isHidden = true
        rebuildHeader()
    }

    @objc private func showSettingsPanel() {
        currentPanel = .settings
        scrollView.isHidden = true
        settingsContainer.isHidden = false
        rebuildSettings()
        rebuildHeader()
    }

    // MARK: - Settings panel

    private func rebuildSettings() {
        settingsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        settingsContainer.addArrangedSubview(makeThemeSection())
        settingsContainer.addArrangedSubview(makeDivider())
        settingsContainer.addArrangedSubview(makePathsSection())
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .semibold)
        f.alignment = .left
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    private func sectionHint(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 11, weight: .regular)
        f.textColor = .secondaryLabelColor
        f.alignment = .left
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    private func makeDivider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private func makeThemeSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(sectionTitle("Touch Bar 主题"))
        section.addArrangedSubview(sectionHint("点击切换。按钮背景与文字颜色 = 该主题实际渲染效果。"))

        let columns = 4
        let currentThemeName = PreferenceStore.shared.themeName
        var index = 0
        while index < Theme.all.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            row.alignment = .centerY
            row.heightAnchor.constraint(equalToConstant: 32).isActive = true

            for _ in 0..<columns {
                if index < Theme.all.count {
                    let theme = Theme.all[index]
                    let isActive = theme.name == currentThemeName
                    let btn = makeThemePreviewButton(theme: theme, index: index, isActive: isActive)
                    btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
                    row.addArrangedSubview(btn)
                    index += 1
                } else {
                    let placeholder = NSView()
                    placeholder.setContentHuggingPriority(.defaultLow, for: .horizontal)
                    placeholder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                    row.addArrangedSubview(placeholder)
                }
            }
            section.addArrangedSubview(row)
        }
        return section
    }

    private func makeThemePreviewButton(theme: Theme, index: Int, isActive: Bool) -> NSView {
        let title = isActive ? "✓  \(theme.displayName)" : theme.displayName

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 6
        wrapper.layer?.backgroundColor = (theme.barBackground ?? NSColor.black).cgColor
        if isActive {
            wrapper.layer?.borderWidth = 1.5
            wrapper.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }

        let button = NSButton(title: title, target: self, action: #selector(pickTheme(_:)))
        button.tag = index
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.secondaryText,
            .font: NSFont.systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)

        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 5),
            button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -5),
            button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
        ])
        return wrapper
    }

    private func makePathsSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 8

        let titleLabel = sectionTitle("路径")
        section.addArrangedSubview(titleLabel)
        let hintLabel = sectionHint("未手动指定时使用自动检测；手动路径优先。")
        section.addArrangedSubview(hintLabel)

        let claudeRow = makePathRow(
            labelText: "Claude Code",
            valueText: claudePathLabel,
            pickAction: #selector(pickClaudeOverride),
            clearAction: #selector(clearClaudeOverride),
            canClear: PreferenceStore.shared.claudeBinOverride != nil
        )
        section.addArrangedSubview(claudeRow)

        let ccRow = makePathRow(
            labelText: "CC Switch DB",
            valueText: ccSwitchPathLabel,
            pickAction: #selector(pickCCSwitchOverride),
            clearAction: #selector(clearCCSwitchOverride),
            canClear: PreferenceStore.shared.ccSwitchDBOverride != nil
        )
        section.addArrangedSubview(ccRow)

        return section
    }

    private func makePathRow(labelText: String,
                              valueText: String,
                              pickAction: Selector,
                              clearAction: Selector,
                              canClear: Bool) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let label = NSTextField(labelWithString: labelText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let value = NSTextField(wrappingLabelWithString: valueText)
        value.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.isEditable = false
        value.isSelectable = true
        value.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 6
        buttonsStack.alignment = .centerY

        let pickBtn = NSButton(title: "选择…", target: self, action: pickAction)
        pickBtn.bezelStyle = .rounded

        let clearBtn = NSButton(title: "清除", target: self, action: clearAction)
        clearBtn.bezelStyle = .rounded
        clearBtn.isEnabled = canClear

        buttonsStack.addArrangedSubview(pickBtn)
        buttonsStack.addArrangedSubview(clearBtn)

        row.addArrangedSubview(label)
        row.addArrangedSubview(value)
        row.addArrangedSubview(buttonsStack)
        return row
    }

    private var claudePathLabel: String {
        let claude = ClaudeDetector.resolvedBinary()
        let tag = PreferenceStore.shared.claudeBinOverride != nil ? "（手动）" : "（自动 - \(claude.source.rawValue)）"
        if let p = claude.path { return "\(p) \(tag)" }
        return "未找到 \(tag)"
    }

    private var ccSwitchPathLabel: String {
        let cc = AppPathsResolver.resolvedCCSwitchDB()
        let tag = PreferenceStore.shared.ccSwitchDBOverride != nil ? "（手动）" : "（自动 - \(cc.source.rawValue)）"
        if let u = cc.url { return "\(u.path) \(tag)" }
        return "未找到 \(tag)"
    }

    @objc private func pickTheme(_ sender: NSButton) {
        let i = sender.tag
        if i >= 0 && i < Theme.all.count {
            PreferenceStore.shared.themeName = Theme.all[i].name
            onThemeChanged?()
            rebuildSettings()
        }
    }

    @objc private func pickClaudeOverride() {
        let panel = NSOpenPanel()
        panel.title = "选择 claude 可执行文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            PreferenceStore.shared.claudeBinOverride = url.path
            onPathsChanged?()
            rebuildSettings()
        }
    }

    @objc private func pickCCSwitchOverride() {
        let panel = NSOpenPanel()
        panel.title = "选择 cc-switch.db"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cc-switch")
        if panel.runModal() == .OK, let url = panel.url {
            PreferenceStore.shared.ccSwitchDBOverride = url.path
            onPathsChanged?()
            rebuildSettings()
        }
    }

    @objc private func clearClaudeOverride() {
        PreferenceStore.shared.claudeBinOverride = nil
        onPathsChanged?()
        rebuildSettings()
    }

    @objc private func clearCCSwitchOverride() {
        PreferenceStore.shared.ccSwitchDBOverride = nil
        onPathsChanged?()
        rebuildSettings()
    }

    // MARK: - Footer

    private func rebuildFooter() {
        footerView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let installButton = NSButton(title: footerButtonTitle, target: self, action: #selector(toggleHooks))
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = ""

        let diagButton = NSButton(title: "诊断", target: self, action: #selector(showDiagnostics))
        diagButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "刷新", target: self, action: #selector(reloadAll))
        reloadButton.bezelStyle = .rounded

        let restartButton = NSButton(title: "重启 Touch Bar", target: self, action: #selector(restartTouchBar))
        restartButton.bezelStyle = .rounded

        footerView.addArrangedSubview(installButton)
        footerView.addArrangedSubview(diagButton)
        footerView.addArrangedSubview(restartButton)
        footerView.addArrangedSubview(NSStackView.horizontalSpacer())
        footerView.addArrangedSubview(reloadButton)
    }

    @objc private func restartTouchBar() {
        onRestartTouchBar?()
    }

    private func makeChip(label: String, color: NSColor) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 4
        container.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 11, weight: .medium)

        container.addArrangedSubview(dot)
        container.addArrangedSubview(text)
        return container
    }

    private var sourceLabel: String {
        switch state?.activeSource ?? .official {
        case .official: return "L1 官方"
        case .envVars(let baseURL): return "L2 env"
        case .ccSwitch: return "L3 cc switch"
        }
    }

    private var footerButtonTitle: String {
        if PreferenceStore.shared.hooksInstalled {
            return "卸载 Hook 监听"
        }
        return "安装 Hook 监听"
    }

    @objc private func toggleHooks() {
        if PreferenceStore.shared.hooksInstalled {
            let r = HookInstaller.uninstall()
            if let err = r.error {
                showAlert(text: err)
            } else {
                rebuildFooter()
            }
        } else {
            let r = HookInstaller.install()
            if let err = r.error {
                showAlert(text: err)
            } else {
                rebuildFooter()
            }
        }
    }

    @objc private func showDiagnostics() {
        guard let state else { return }
        let alert = NSAlert()
        alert.messageText = "诊断信息"
        alert.informativeText = state.bootDiagnostics.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func reloadAll() {
        Task { @MainActor in
            bridge?.reload()
            tableView.reloadData()
            rebuildHeader()
        }
    }

    private func showAlert(text: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return sessions?.activeSessions.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let sessions,
              row < sessions.activeSessions.count else { return nil }
        let s = sessions.activeSessions[row]
        let focused = (sessions.focusedSessionID == s.id)

        let cell = SessionRowView(session: s, focused: focused)
        cell.onActivate = { [weak self] in
            self?.activate(session: s)
        }
        return cell
    }

    private func activate(session: Session) {
        WindowActivator.activate(session: session)
    }
}

@MainActor
final class SessionRowView: NSView {

    var onActivate: (() -> Void)?

    init(session: Session, focused: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = focused
            ? NSColor.systemBlue.withAlphaComponent(0.08).cgColor
            : NSColor.clear.cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])

        // status dot
        let iconView = StatusIconView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        iconView.update(mode: mapStatus(session.status))

        // project name
        let title = NSTextField(labelWithString: session.projectName)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = focused ? .controlAccentColor : .labelColor

        // cwd
        let cwd = NSTextField(labelWithString: session.displayCwd)
        cwd.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        cwd.textColor = .secondaryLabelColor
        cwd.lineBreakMode = .byTruncatingMiddle
        cwd.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // duration
        let duration = NSTextField(labelWithString: formatDuration(session.duration))
        duration.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        duration.textColor = .tertiaryLabelColor

        // hostApp
        let host = NSTextField(labelWithString: session.hostApp)
        host.font = .systemFont(ofSize: 10, weight: .regular)
        host.textColor = .tertiaryLabelColor

        // activate
        let button = NSButton(title: "激活", target: self, action: #selector(activateClicked))
        button.bezelStyle = .rounded
        button.controlSize = .small

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(cwd)
        stack.addArrangedSubview(NSStackView.horizontalSpacer())
        stack.addArrangedSubview(duration)
        stack.addArrangedSubview(host)
        stack.addArrangedSubview(button)

        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func activateClicked() {
        onActivate?()
    }

    private func mapStatus(_ s: Session.Status) -> StatusIconView.Mode {
        switch s {
        case .idle: return .idle
        case .thinking: return .thinking
        case .streaming: return .streaming
        case .stopped: return .stopped
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m\(s%60)s" }
        return "\(s/3600)h\(s/60%60)m"
    }
}

extension NSStackView {
    static func horizontalSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }
}
