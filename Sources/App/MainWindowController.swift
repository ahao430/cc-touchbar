import AppKit
import Observation

@MainActor
final class MainWindowController: NSWindowController {

    private weak var state: AppState?
    private weak var sessions: SessionStore?
    private weak var bridge: CCSwitchBridge?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerView = NSStackView()
    private let footerView = NSStackView()

    private var observerToken: Any?

    /// 路径覆盖变化后由 AppDelegate 重新跑诊断 + 刷 HUD
    var onPathsChanged: (() -> Void)?

    /// 主题切换后由 AppDelegate 把新主题推到 TouchBarController
    var onThemeChanged: (() -> Void)?

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

        contentView.addSubview(headerView)
        contentView.addSubview(scrollView)
        contentView.addSubview(footerView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        rebuildHeader()
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

    private func rebuildHeader() {
        headerView.arrangedSubviews.forEach { $0.removeFromSuperview() }

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
    }

    private func rebuildFooter() {
        footerView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let installButton = NSButton(title: footerButtonTitle, target: self, action: #selector(toggleHooks))
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = ""

        let pathButton = NSButton(title: "路径…", target: self, action: #selector(showPaths))
        pathButton.bezelStyle = .rounded

        let themeButton = NSButton(title: "主题…", target: self, action: #selector(showThemes))
        themeButton.bezelStyle = .rounded

        let diagButton = NSButton(title: "诊断", target: self, action: #selector(showDiagnostics))
        diagButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "重新加载", target: self, action: #selector(reloadAll))
        reloadButton.bezelStyle = .rounded

        footerView.addArrangedSubview(installButton)
        footerView.addArrangedSubview(pathButton)
        footerView.addArrangedSubview(themeButton)
        footerView.addArrangedSubview(diagButton)
        footerView.addArrangedSubview(NSStackView.horizontalSpacer())
        footerView.addArrangedSubview(reloadButton)
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

    @objc private func showThemes() {
        let current = PreferenceStore.shared.themeName
        let alert = NSAlert()
        alert.messageText = "Touch Bar 主题"
        alert.informativeText = "当前：\(Theme.current().displayName)\n黑底 → 白字；浅色主题会给每个 item 加白底，便于显示深色文字。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "关闭")
        for theme in Theme.all {
            let btn = alert.addButton(withTitle: "切换到\(theme.displayName)")
            btn.tag = 0
            _ = btn
        }
        let resp = alert.runModal()
        let firstThemeBtn = NSApplication.ModalResponse.alertSecondButtonReturn.rawValue
        let index = resp.rawValue - firstThemeBtn
        if index >= 0 && index < Theme.all.count {
            let picked = Theme.all[index]
            PreferenceStore.shared.themeName = picked.name
            onThemeChanged?()
        }
    }

    @objc private func showPaths() {
        let claude = ClaudeDetector.resolvedBinary()
        let cc = AppPathsResolver.resolvedCCSwitchDB()

        let claudeLine: String = {
            if let p = claude.path {
                let tag = PreferenceStore.shared.claudeBinOverride != nil ? "（手动）" : "（自动 - \(claude.source.rawValue)）"
                return "Claude Code: \(p) \(tag)"
            }
            return "Claude Code: 未找到（自动 - \(claude.source.rawValue)）"
        }()
        let ccLine: String = {
            if let u = cc.url {
                let tag = PreferenceStore.shared.ccSwitchDBOverride != nil ? "（手动）" : "（自动 - \(cc.source.rawValue)）"
                return "CC Switch DB: \(u.path) \(tag)"
            }
            return "CC Switch DB: 未找到（自动 - \(cc.source.rawValue)）"
        }()

        let alert = NSAlert()
        alert.messageText = "路径设置"
        alert.informativeText = "\(claudeLine)\n\(ccLine)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "选择 Claude…")
        alert.addButton(withTitle: "选择 CC Switch DB…")
        alert.addButton(withTitle: "清除所有覆盖")
        let resp = alert.runModal()
        switch resp.rawValue {
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
            pickClaudeOverride()
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue:
            pickCCSwitchOverride()
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1:
            PreferenceStore.shared.claudeBinOverride = nil
            PreferenceStore.shared.ccSwitchDBOverride = nil
            onPathsChanged?()
            showPaths()
        default:
            break
        }
    }

    private func pickClaudeOverride() {
        let panel = NSOpenPanel()
        panel.title = "选择 claude 可执行文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            PreferenceStore.shared.claudeBinOverride = url.path
            onPathsChanged?()
            showPaths()
        }
    }

    private func pickCCSwitchOverride() {
        let panel = NSOpenPanel()
        panel.title = "选择 cc-switch.db"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cc-switch")
        if panel.runModal() == .OK, let url = panel.url {
            PreferenceStore.shared.ccSwitchDBOverride = url.path
            onPathsChanged?()
            showPaths()
        }
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
