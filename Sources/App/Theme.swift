import AppKit

/// Touch Bar 主题。规则：
/// - 默认主题：系统 Touch Bar 黑底 → 文字用白
/// - 深色文字主题：每个 item 加浅色背景层，让深色文字看得清
@MainActor
struct Theme {

    let name: String
    let displayName: String

    /// 主文本（供应商 / 按钮标题）
    let primaryText: NSColor
    /// 次级文本（模型 / 余额 / 时长）
    let secondaryText: NSColor
    /// 供应商按钮 bezel 填充
    let providerBezel: NSColor
    /// 供应商按钮文字（无论主题，确保在 bezel 上读得清）
    let providerText: NSColor
    /// 单个 item 背景层；nil = 透明（沿用系统 Touch Bar 的深色）
    let itemBackground: NSColor?
    /// 强调色（图标按钮的 tint）
    let accent: NSColor
    /// 分隔线颜色
    let separatorColor: NSColor

    static let dark = Theme(
        name: "Dark",
        displayName: "深色（默认）",
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.78),
        providerBezel: NSColor.systemBlue.withAlphaComponent(0.35),
        providerText: .white,
        itemBackground: nil,
        accent: NSColor.systemBlue,
        separatorColor: NSColor.white.withAlphaComponent(0.45)
    )

    static let light = Theme(
        name: "Light",
        displayName: "浅色",
        primaryText: NSColor(white: 0.08, alpha: 1.0),
        secondaryText: NSColor(white: 0.32, alpha: 1.0),
        providerBezel: NSColor.systemBlue.withAlphaComponent(0.85),
        providerText: .white,
        itemBackground: NSColor(white: 0.92, alpha: 1.0),
        accent: NSColor.systemBlue,
        separatorColor: NSColor(white: 0.0, alpha: 0.35)
    )

    static var all: [Theme] { [dark, light] }

    static func current() -> Theme {
        let stored = PreferenceStore.shared.themeName
        return all.first(where: { $0.name == stored }) ?? dark
    }
}
