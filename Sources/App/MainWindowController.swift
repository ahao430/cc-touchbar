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
    private let settingsScrollView = NSScrollView()
    private let settingsContentView = NSView()
    private let settingsContainer = NSStackView()

    private var currentPanel: MainPanel = .sessions
    private var observerToken: Any?

    /// 设置面板里的两个间隔输入框 + stepper，apply / stepper 变化时读写
    private weak var pollIntervalField: NSTextField?
    private weak var pollIntervalStepper: NSStepper?
    private weak var balanceIntervalField: NSTextField?
    private weak var balanceIntervalStepper: NSStepper?
    private weak var backgroundOpacitySlider: NSSlider?
    private weak var backgroundBlurSlider: NSSlider?
    private weak var backgroundCropXSlider: NSSlider?
    private weak var backgroundCropYSlider: NSSlider?
    private weak var backgroundCropZoomSlider: NSSlider?
    private weak var backgroundOpacityValueLabel: NSTextField?
    private weak var backgroundBlurValueLabel: NSTextField?
    private weak var backgroundCropXValueLabel: NSTextField?
    private weak var backgroundCropYValueLabel: NSTextField?
    private weak var backgroundCropZoomValueLabel: NSTextField?
    private weak var backgroundPreviewView: NSView?
    private weak var backgroundPreviewLabel: NSTextField?
    private var themePreviewButtons: [NSButton] = []
    private var themePreviewWrappers: [NSView] = []
    private var cachedPreviewKey: String?
    private var cachedPreviewImage: CGImage?
    private static let ciContext = CIContext()
    private static let touchBarAspect: CGFloat = 1085.0 / 30.0

    /// 路径覆盖变化后由 AppDelegate 重新跑诊断 + 刷 HUD
    var onPathsChanged: (() -> Void)?

    /// 主题切换后由 AppDelegate 把新主题推到 TouchBarController
    var onThemeChanged: (() -> Void)?

    /// 重启 Touch Bar（DFR dismiss + 重新 make + present）
    var onRestartTouchBar: (() -> Void)?

    /// 轮询间隔变化后由 AppDelegate 重建 transcript / 余额定时器
    var onIntervalsChanged: (() -> Void)?

    /// 订阅百分比口径变化后由 AppDelegate 重新拉取并刷新 HUD
    var onSubscriptionPercentModeChanged: (() -> Void)?

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
        headerView.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 12, right: 16)
        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Footer
        footerView.orientation = .horizontal
        footerView.spacing = 8
        footerView.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 18, right: 16)
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
        settingsScrollView.documentView = settingsContentView
        settingsScrollView.hasVerticalScroller = true
        settingsScrollView.autohidesScrollers = false
        settingsScrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.isHidden = true

        settingsContentView.translatesAutoresizingMaskIntoConstraints = false

        settingsContainer.orientation = .vertical
        settingsContainer.alignment = .leading
        settingsContainer.spacing = 18
        settingsContainer.edgeInsets = NSEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false

        settingsContentView.addSubview(settingsContainer)

        contentView.addSubview(headerView)
        contentView.addSubview(scrollView)
        contentView.addSubview(settingsScrollView)
        contentView.addSubview(footerView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            settingsScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            settingsScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            settingsScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            settingsScrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            settingsContentView.leadingAnchor.constraint(equalTo: settingsScrollView.contentView.leadingAnchor),
            settingsContentView.topAnchor.constraint(equalTo: settingsScrollView.contentView.topAnchor),
            settingsContentView.widthAnchor.constraint(equalTo: settingsScrollView.contentView.widthAnchor),
            settingsContentView.bottomAnchor.constraint(equalTo: settingsContainer.bottomAnchor, constant: 20),

            settingsContainer.topAnchor.constraint(equalTo: settingsContentView.topAnchor),
            settingsContainer.leadingAnchor.constraint(equalTo: settingsContentView.leadingAnchor, constant: 16),
            settingsContainer.widthAnchor.constraint(equalToConstant: 600),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        window?.minSize = NSSize(width: 640, height: 260)

        rebuildHeader()
        rebuildFooter()
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
        settingsScrollView.isHidden = true
        rebuildHeader()
        rebuildFooter()
    }

    @objc private func showSettingsPanel() {
        currentPanel = .settings
        scrollView.isHidden = true
        settingsScrollView.isHidden = false
        rebuildSettings()
        rebuildHeader()
        rebuildFooter()
    }

    // MARK: - Settings panel

    private func rebuildSettings() {
        settingsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        settingsContainer.addArrangedSubview(makeThemeSection())
        settingsContainer.addArrangedSubview(makeDivider())
        settingsContainer.addArrangedSubview(makeBackgroundSection())
        settingsContainer.addArrangedSubview(makeDivider())
        settingsContainer.addArrangedSubview(makePathsSection())
        settingsContainer.addArrangedSubview(makeDivider())
        settingsContainer.addArrangedSubview(makeIntervalsSection())
        settingsContainer.addArrangedSubview(makeDivider())
        settingsContainer.addArrangedSubview(makeSubscriptionSection())
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
        section.addArrangedSubview(sectionHint("点击选择主题，保存后应用到 Touch Bar。按钮背景与文字颜色 = 该主题实际渲染效果。"))

        themePreviewButtons.removeAll()
        themePreviewWrappers.removeAll()
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
        themePreviewWrappers.append(wrapper)
        themePreviewButtons.append(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 5),
            button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -5),
            button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
        ])
        return wrapper
    }

    private func makeBackgroundSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(sectionTitle("Touch Bar 背景图"))
        section.addArrangedSubview(sectionHint("可选。图片会铺满 HUD 背景；文字颜色仍跟随当前主题。"))

        let row = makePathRow(
            labelText: "背景图",
            valueText: touchBarBackgroundImageLabel,
            pickAction: #selector(pickTouchBarBackgroundImage),
            clearAction: #selector(clearTouchBarBackgroundImage),
            canClear: PreferenceStore.shared.touchBarBackgroundImagePath != nil
        )
        section.addArrangedSubview(row)
        section.addArrangedSubview(makeBackgroundPreview())

        let opacityRow = makeBackgroundSliderRow(labelText: "不透明度", value: PreferenceStore.shared.touchBarBackgroundOpacity, min: 0, max: 1, action: #selector(backgroundSliderChanged(_:)))
        backgroundOpacitySlider = opacityRow.slider
        backgroundOpacityValueLabel = opacityRow.valueLabel
        section.addArrangedSubview(opacityRow.view)

        let blurRow = makeBackgroundSliderRow(labelText: "模糊像素", value: PreferenceStore.shared.touchBarBackgroundBlurRadius, min: 0, max: 30, action: #selector(backgroundSliderChanged(_:)))
        backgroundBlurSlider = blurRow.slider
        backgroundBlurValueLabel = blurRow.valueLabel
        section.addArrangedSubview(blurRow.view)

        let cropXRow = makeBackgroundSliderRow(labelText: "区域左右", value: PreferenceStore.shared.touchBarBackgroundCropX, min: 0, max: 1, action: #selector(backgroundSliderChanged(_:)))
        backgroundCropXSlider = cropXRow.slider
        backgroundCropXValueLabel = cropXRow.valueLabel
        section.addArrangedSubview(cropXRow.view)

        let cropYRow = makeBackgroundSliderRow(labelText: "区域上下", value: PreferenceStore.shared.touchBarBackgroundCropY, min: 0, max: 1, action: #selector(backgroundSliderChanged(_:)))
        backgroundCropYSlider = cropYRow.slider
        backgroundCropYValueLabel = cropYRow.valueLabel
        section.addArrangedSubview(cropYRow.view)

        let zoomRow = makeBackgroundSliderRow(labelText: "区域缩放", value: PreferenceStore.shared.touchBarBackgroundCropZoom, min: 1, max: 5, action: #selector(backgroundSliderChanged(_:)))
        backgroundCropZoomSlider = zoomRow.slider
        backgroundCropZoomValueLabel = zoomRow.valueLabel
        section.addArrangedSubview(zoomRow.view)

        return section
    }

    private var touchBarBackgroundImageLabel: String {
        PreferenceStore.shared.touchBarBackgroundImagePath ?? "未设置（使用主题背景色）"
    }

    private func makeBackgroundPreview() -> NSView {
        let preview = NSView()
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.masksToBounds = true
        preview.heightAnchor.constraint(equalToConstant: 44).isActive = true
        backgroundPreviewView = preview
        updateBackgroundPreview()

        let label = NSTextField(labelWithString: "Touch Bar 背景预览")
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(label)
        backgroundPreviewLabel = label
        updateBackgroundPreviewLabel()
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: preview.centerYAnchor)
        ])
        return preview
    }

    private func updateBackgroundPreview() {
        guard let layer = backgroundPreviewView?.layer else { return }
        layer.backgroundColor = Theme.current().barBackground?.cgColor
        layer.contents = nil
        layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let path = PreferenceStore.shared.touchBarBackgroundImagePath,
           let image = processedBackgroundImage(from: path) {
            layer.contents = image
            layer.contentsGravity = .resizeAspectFill
            layer.contentsRect = backgroundContentsRect(for: image)
        }
        updateBackgroundPreviewLabel()
    }

    private func updateBackgroundPreviewLabel() {
        backgroundPreviewLabel?.textColor = Theme.current().primaryText
    }

    private func backgroundContentsRect(for image: CGImage) -> CGRect {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let targetAspect = Self.touchBarAspect
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        if imageAspect > targetAspect {
            baseHeight = 1
            baseWidth = targetAspect / imageAspect
        } else {
            baseWidth = 1
            baseHeight = imageAspect / targetAspect
        }
        let zoom = CGFloat(PreferenceStore.shared.touchBarBackgroundCropZoom)
        let width = baseWidth / zoom
        let height = baseHeight / zoom
        let x = CGFloat(PreferenceStore.shared.touchBarBackgroundCropX) * (1 - width)
        let y = CGFloat(PreferenceStore.shared.touchBarBackgroundCropY) * (1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func processedBackgroundImage(from path: String) -> CGImage? {
        let key = "\(path)|\(PreferenceStore.shared.touchBarBackgroundBlurRadius)|\(PreferenceStore.shared.touchBarBackgroundOpacity)"
        if cachedPreviewKey == key, let cachedPreviewImage {
            return cachedPreviewImage
        }
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let blur = PreferenceStore.shared.touchBarBackgroundBlurRadius
        let output: CIImage
        if blur > 0,
           let blurFilter = CIFilter(name: "CIGaussianBlur"),
           let cropFilter = CIFilter(name: "CICrop") {
            blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
            blurFilter.setValue(blur, forKey: kCIInputRadiusKey)
            cropFilter.setValue(blurFilter.outputImage, forKey: kCIInputImageKey)
            cropFilter.setValue(CIVector(cgRect: ciImage.extent), forKey: "inputRectangle")
            output = cropFilter.outputImage ?? ciImage
        } else {
            output = ciImage
        }
        guard let alphaFilter = CIFilter(name: "CIColorMatrix") else { return cgImage }
        alphaFilter.setValue(output, forKey: kCIInputImageKey)
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: PreferenceStore.shared.touchBarBackgroundOpacity), forKey: "inputAVector")
        let processed = Self.ciContext.createCGImage(alphaFilter.outputImage ?? output, from: ciImage.extent) ?? cgImage
        cachedPreviewKey = key
        cachedPreviewImage = processed
        return processed
    }

    private func makeBackgroundSliderRow(labelText: String,
                                         value: Double,
                                         min: Double,
                                         max: Double,
                                         action: Selector) -> (view: NSView, slider: NSSlider, valueLabel: NSTextField) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let label = NSTextField(labelWithString: labelText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let valueLabel = NSTextField(labelWithString: formatBackgroundSliderValue(labelText: labelText, value: value))
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        return (row, slider, valueLabel)
    }

    private func formatBackgroundSliderValue(labelText: String, value: Double) -> String {
        String(format: labelText == "模糊像素" ? "%.0f" : "%.2f", value)
    }

    private func makePathsSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
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

    private func makeIntervalsSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(sectionTitle("轮询间隔"))
        section.addArrangedSubview(sectionHint("Transcript / Git 分支检测：范围 0.5–60s；订阅余额刷新：范围 5–3600s。输入框只允许数字和小数点；点上下箭头 ±1s 即时生效；输入后点「应用」校验并生效。"))

        let (pollRow, pollField, pollStepper) = makeIntervalRow(
            labelText: "Transcript / Git 分支",
            value: PreferenceStore.shared.pollIntervalSeconds,
            minValue: 0.5,
            maxValue: 60,
            applyAction: #selector(applyPollInterval),
            stepperAction: #selector(pollStepperChanged(_:))
        )
        pollIntervalField = pollField
        pollIntervalStepper = pollStepper
        section.addArrangedSubview(pollRow)

        let (balanceRow, balanceField, balanceStepper) = makeIntervalRow(
            labelText: "订阅余额",
            value: PreferenceStore.shared.balanceIntervalSeconds,
            minValue: 5,
            maxValue: 3600,
            applyAction: #selector(applyBalanceInterval),
            stepperAction: #selector(balanceStepperChanged(_:))
        )
        balanceIntervalField = balanceField
        balanceIntervalStepper = balanceStepper
        section.addArrangedSubview(balanceRow)

        return section
    }

    private func makeIntervalRow(labelText: String,
                                  value: Double,
                                  minValue: Double,
                                  maxValue: Double,
                                  applyAction: Selector,
                                  stepperAction: Selector) -> (NSView, NSTextField, NSStepper) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let label = NSTextField(labelWithString: labelText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.isPartialStringValidationEnabled = true

        let field = NSTextField()
        field.formatter = formatter
        field.stringValue = String(format: "%.1f", value)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        field.target = self
        field.action = applyAction

        let suffixLabel = NSTextField(labelWithString: "秒")
        suffixLabel.textColor = .secondaryLabelColor
        suffixLabel.font = .systemFont(ofSize: 11)

        let stepper = NSStepper()
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.doubleValue = value
        stepper.target = self
        stepper.action = stepperAction

        let applyBtn = NSButton(title: "应用", target: self, action: applyAction)
        applyBtn.bezelStyle = .rounded

        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(suffixLabel)
        row.addArrangedSubview(stepper)
        row.addArrangedSubview(applyBtn)
        return (row, field, stepper)
    }

    private func makeSubscriptionSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8

        section.addArrangedSubview(sectionTitle("订阅百分比显示"))
        section.addArrangedSubview(sectionHint("订阅类型（如智谱 Token Plan）的百分比显示口径。默认剩余百分比。"))

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let label = NSTextField(labelWithString: "百分比口径")
        label.font = .systemFont(ofSize: 12, weight: .medium)

        let seg = NSSegmentedControl(labels: ["剩余百分比", "已用百分比"], trackingMode: .selectOne, target: self, action: #selector(subscriptionPercentModeChanged(_:)))
        seg.selectedSegment = PreferenceStore.shared.subscriptionPercentMode == .remaining ? 0 : 1

        row.addArrangedSubview(label)
        row.addArrangedSubview(seg)
        section.addArrangedSubview(row)
        return section
    }


    @objc private func applySettings() {
        onThemeChanged?()
    }

    @objc private func subscriptionPercentModeChanged(_ sender: NSSegmentedControl) {
        PreferenceStore.shared.subscriptionPercentMode = sender.selectedSegment == 0 ? .remaining : .used
        onSubscriptionPercentModeChanged?()
    }

    @objc private func pickTheme(_ sender: NSButton) {
        let i = sender.tag
        if i >= 0 && i < Theme.all.count {
            PreferenceStore.shared.themeName = Theme.all[i].name
            updateThemeSelection()
            updateBackgroundPreview()
        }
    }

    private func updateThemeSelection() {
        let currentThemeName = PreferenceStore.shared.themeName
        for (index, button) in themePreviewButtons.enumerated() {
            guard index < Theme.all.count else { continue }
            let theme = Theme.all[index]
            let isActive = theme.name == currentThemeName
            let title = isActive ? "✓  \(theme.displayName)" : theme.displayName
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: theme.secondaryText,
                .font: NSFont.systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
            ])
            let wrapper = themePreviewWrappers[index]
            wrapper.layer?.borderWidth = isActive ? 1.5 : 0
            wrapper.layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    @objc private func pickTouchBarBackgroundImage() {
        let panel = NSOpenPanel()
        panel.title = "选择 Touch Bar 背景图"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            PreferenceStore.shared.touchBarBackgroundImagePath = url.path
            PreferenceStore.shared.touchBarBackgroundCropX = 0.5
            PreferenceStore.shared.touchBarBackgroundCropY = 0.5
            PreferenceStore.shared.touchBarBackgroundCropZoom = 1
            rebuildSettings()
        }
    }

    @objc private func clearTouchBarBackgroundImage() {
        PreferenceStore.shared.touchBarBackgroundImagePath = nil
        rebuildSettings()
    }

    @objc private func backgroundSliderChanged(_ sender: NSSlider) {
        if sender === backgroundOpacitySlider {
            PreferenceStore.shared.touchBarBackgroundOpacity = sender.doubleValue
            backgroundOpacityValueLabel?.stringValue = formatBackgroundSliderValue(labelText: "不透明度", value: sender.doubleValue)
            cachedPreviewKey = nil
            cachedPreviewImage = nil
        } else if sender === backgroundBlurSlider {
            PreferenceStore.shared.touchBarBackgroundBlurRadius = sender.doubleValue
            backgroundBlurValueLabel?.stringValue = formatBackgroundSliderValue(labelText: "模糊像素", value: sender.doubleValue)
            cachedPreviewKey = nil
            cachedPreviewImage = nil
        } else if sender === backgroundCropXSlider {
            PreferenceStore.shared.touchBarBackgroundCropX = sender.doubleValue
            backgroundCropXValueLabel?.stringValue = formatBackgroundSliderValue(labelText: "区域左右", value: sender.doubleValue)
        } else if sender === backgroundCropYSlider {
            PreferenceStore.shared.touchBarBackgroundCropY = sender.doubleValue
            backgroundCropYValueLabel?.stringValue = formatBackgroundSliderValue(labelText: "区域上下", value: sender.doubleValue)
        } else if sender === backgroundCropZoomSlider {
            PreferenceStore.shared.touchBarBackgroundCropZoom = sender.doubleValue
            backgroundCropZoomValueLabel?.stringValue = formatBackgroundSliderValue(labelText: "区域缩放", value: sender.doubleValue)
        }
        updateBackgroundPreview()
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

    @objc private func applyPollInterval() {
        guard let field = pollIntervalField else { return }
        guard let v = parseInterval(field: field, min: 0.5, max: 60,
                                     message: "Transcript / Git 分支间隔必须在 0.5 – 60 秒之间") else { return }
        PreferenceStore.shared.pollIntervalSeconds = v
        pollIntervalStepper?.doubleValue = v
        onIntervalsChanged?()
    }

    @objc private func applyBalanceInterval() {
        guard let field = balanceIntervalField else { return }
        guard let v = parseInterval(field: field, min: 5, max: 3600,
                                     message: "订阅余额刷新间隔必须在 5 – 3600 秒之间") else { return }
        PreferenceStore.shared.balanceIntervalSeconds = v
        balanceIntervalStepper?.doubleValue = v
        onIntervalsChanged?()
    }

    @objc private func pollStepperChanged(_ sender: NSStepper) {
        let v = sender.doubleValue
        PreferenceStore.shared.pollIntervalSeconds = v
        pollIntervalField?.stringValue = String(format: "%.1f", v)
        onIntervalsChanged?()
    }

    @objc private func balanceStepperChanged(_ sender: NSStepper) {
        let v = sender.doubleValue
        PreferenceStore.shared.balanceIntervalSeconds = v
        balanceIntervalField?.stringValue = String(format: "%.1f", v)
        onIntervalsChanged?()
    }

    /// 解析输入框：失败 / 越界时弹窗并返回 nil
    private func parseInterval(field: NSTextField, min: Double, max: Double, message: String) -> Double? {
        let raw = field.stringValue.trimmingCharacters(in: .whitespaces)
        let formatter = NumberFormatter()
        formatter.decimalSeparator = "."
        guard let n = formatter.number(from: raw) else {
            showIntervalAlert("请输入有效的数字。")
            return nil
        }
        let v = n.doubleValue
        guard v >= min && v <= max else {
            showIntervalAlert(message)
            return nil
        }
        return v
    }

    private func showIntervalAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "输入无效"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
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

        let updateButton = NSButton(title: "检查更新", target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded

        let restartButton = NSButton(title: "重启 Touch Bar", target: self, action: #selector(restartTouchBar))
        restartButton.bezelStyle = .rounded

        footerView.addArrangedSubview(installButton)
        footerView.addArrangedSubview(diagButton)
        footerView.addArrangedSubview(restartButton)
        footerView.addArrangedSubview(updateButton)
        footerView.addArrangedSubview(NSStackView.horizontalSpacer())
        if currentPanel == .settings {
            let applyButton = NSButton(title: "保存并应用设置", target: self, action: #selector(applySettings))
            applyButton.bezelStyle = .rounded
            footerView.addArrangedSubview(applyButton)
        }
        footerView.addArrangedSubview(reloadButton)
    }

    @objc private func restartTouchBar() {
        onRestartTouchBar?()
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
            alert.informativeText = "当前版本 \(current)，新版本 \(latest) 已发布。是否立即前往下载？"
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
        rebuildFooter()
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
