import AppKit
import Foundation
import ObjectiveC

// MTMR 同款私有 API：DFRSupport framework 里的 C 函数（实际已合并进 AppKit）
// 静态链接器找不到这些符号，必须运行时通过 dlsym 解析
private func loadDFRSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    if let h = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY|RTLD_NOLOAD) {
        if let s = dlsym(h, name) { return s }
    }
    if let h = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY) {
        if let s = dlsym(h, name) { return s }
    }
    if let h = dlopen("/System/Library/PrivateFrameworks/DFRSupport.framework/DFRSupport", RTLD_LAZY) {
        if let s = dlsym(h, name) { return s }
    }
    return dlsym(dlopen(nil, RTLD_LAZY), name)
}

@MainActor
enum SystemTouchBarPresenter {

    struct Diagnostics: CustomStringConvertible {
        var appResponds: Bool = false
        var lastCall: String = ""
        var message: String = ""

        var description: String {
            """
            SystemTouchBarPresenter 诊断:
              NSApp responds to presentSystemModalTouchBar::: \(appResponds)
              last call: \(lastCall.isEmpty ? "未调用" : lastCall)
              message: \(message.isEmpty ? "无" : message)
            """
        }
    }

    private(set) static var lastDiagnostics = Diagnostics()
    private static var presentedBar: NSTouchBar?
    private static let identifier = "com.cctouchbar.app.system"

    /// 常驻 Control Strip 的 tray item —— MTMR 风格
    /// 注册一次后，即使 HUD 被 minimize/dismiss，tray 图标依然在 Control Strip
    /// 点击 tray 触发 target/action，调用方在 action 里重新 presentSystemModal
    static let trayIdentifier = "com.cctouchbar.app.tray"
    private static var trayItem: NSCustomTouchBarItem?

    /// 在 Control Strip 注册常驻 tray item
    /// 必须在 NSApplication 启动后、第一次 present 之前调用
    static func setupTrayItem(target: Any, action: Selector, image: NSImage?) {
        if let sym = loadDFRSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost") {
            typealias FnType = @convention(c) (ObjCBool) -> Void
            unsafeBitCast(sym, to: FnType.self)(ObjCBool(false))
        }

        // Claude Code 图标：优先用调用方传入的，其次从 bundle 加载 ClaudeIcon.png
        let icon: NSImage
        if let provided = image {
            icon = provided
        } else if let bundled = loadClaudeIcon() {
            icon = bundled
        } else {
            icon = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "cc-touchbar")
                ?? NSImage(named: NSImage.actionTemplateName)!
        }
        icon.isTemplate = false
        icon.size = NSSize(width: 22, height: 22)

        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(trayIdentifier))
        let button = NSButton(image: icon, target: target, action: action)
        button.bezelStyle = .inline
        item.view = button
        trayItem = item

        let cls: AnyClass = NSTouchBarItem.self
        let sel = NSSelectorFromString("addSystemTrayItem:")
        guard let method = class_getClassMethod(cls, sel) else {
            diagLog("✗ NSTouchBarItem 不响应 addSystemTrayItem:")
            return
        }
        let imp = method_getImplementation(method)
        typealias FnType = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        let fn = unsafeBitCast(imp, to: FnType.self)
        fn(cls, sel, item)

        setTrayPresence(true)
        diagLog("✓ tray item 已注册到 Control Strip")
    }

    private static func loadClaudeIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "ClaudeIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    static func setTrayPresence(_ present: Bool) {
        guard let sym = loadDFRSymbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias FnType = @convention(c) (CFString, ObjCBool) -> Void
        unsafeBitCast(sym, to: FnType.self)(trayIdentifier as CFString, ObjCBool(present))
    }

    /// 把一个 NSTouchBar 呈现为系统模态（即使切到其它 app 也显示）
    /// 使用无 placement 变体 `presentSystemModalTouchBar:systemTrayItemIdentifier:`
    /// + 非空 identifier 让系统在 Control Strip 注册 tray 按钮（折叠后能点回来）
    static func present(_ bar: NSTouchBar) {
        let cls: AnyClass = NSTouchBar.self

        // 优先用无 placement 版本 —— 不带 placement 意味着"和 Control Strip 共存"
        let noPlacementSel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        let withPlacementSel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")

        if let method = class_getClassMethod(cls, noPlacementSel) {
            let imp = method_getImplementation(method)
            typealias FnType = @convention(c) (AnyClass, Selector, NSTouchBar, NSString) -> Void
            let fn = unsafeBitCast(imp, to: FnType.self)
            fn(cls, noPlacementSel, bar, trayIdentifier as NSString)

            presentedBar = bar
            lastDiagnostics.appResponds = true
            lastDiagnostics.lastCall = "present(\(trayIdentifier), no-placement)"
            diagLog("✓ 系统模态 Touch Bar 已 present (无 placement 变体)")
            return
        }

        // 回退：带 placement 的版本，placement=0
        guard let method = class_getClassMethod(cls, withPlacementSel) else {
            lastDiagnostics.appResponds = false
            lastDiagnostics.message = "NSTouchBar 没有这个类方法"
            diagLog("✗ 两个 present 变体都不响应")
            return
        }
        let imp = method_getImplementation(method)
        typealias FnType = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString) -> Void
        let fn = unsafeBitCast(imp, to: FnType.self)
        fn(cls, withPlacementSel, bar, 0, trayIdentifier as NSString)

        presentedBar = bar
        lastDiagnostics.appResponds = true
        lastDiagnostics.lastCall = "present(\(trayIdentifier), placement=0 fallback)"
        diagLog("✓ 系统模态 Touch Bar 已 present (回退到 placement 变体, placement=0)")
    }

    /// 最小化到 Control Strip 托盘 —— 用户点击托盘图标可再次展开
    static func minimize() {
        guard let bar = presentedBar else { return }
        let cls: AnyClass = NSTouchBar.self
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        guard let method = class_getClassMethod(cls, sel) else {
            diagLog("✗ minimizeSystemModalTouchBar: 不存在，回退到 dismiss")
            dismiss()
            return
        }
        let imp = method_getImplementation(method)
        typealias FnType = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let fn = unsafeBitCast(imp, to: FnType.self)
        fn(cls, sel, bar)
        lastDiagnostics.lastCall = "minimize()"
        diagLog("✓ 系统模态 Touch Bar 已 minimize")
    }

    private static func diagLog(_ msg: String) {
        let line = "[cc-touchbar] \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/cc-touchbar-dfr.log")
        if let data = line.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func dismiss() {
        guard let bar = presentedBar else { return }
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        let cls: AnyClass = NSTouchBar.self
        guard let method = class_getClassMethod(cls, sel) else {
            return
        }
        let imp = method_getImplementation(method)
        typealias FnType = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let fn = unsafeBitCast(imp, to: FnType.self)
        fn(cls, sel, bar)
        presentedBar = nil
        lastDiagnostics.lastCall = "dismiss()"
        diagLog("✓ 系统模态 Touch Bar 已 dismiss")
    }
}
