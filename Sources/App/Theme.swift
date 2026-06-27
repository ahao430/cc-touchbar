import AppKit

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

/// Touch Bar 主题。规则：
/// - 默认主题：系统 Touch Bar 黑底 → 文字用白
/// - 自定义主题：整条 HUD 容器加 barBackground 圆角背景层
@MainActor
struct Theme {

    let name: String
    let displayName: String

    /// 主文本（保留用于强调，目前所有 item 统一用 secondaryText）
    let primaryText: NSColor
    /// 次级文本（统一用于所有 label / 无背景按钮）
    let secondaryText: NSColor
    /// 整个 HUD 容器的背景层；nil = 透明（沿用系统 Touch Bar 的深色）
    let barBackground: NSColor?
    /// 强调色（图标按钮的 tint / bezel tint）
    let accent: NSColor
    /// 分隔线颜色
    let separatorColor: NSColor

    static let dark = Theme(
        name: "Dark",
        displayName: "深色（默认）",
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.78),
        barBackground: nil,
        accent: NSColor.systemBlue,
        separatorColor: NSColor.white.withAlphaComponent(0.45)
    )

    static let light = Theme(
        name: "Light",
        displayName: "浅色",
        primaryText: NSColor(white: 0.08, alpha: 1.0),
        secondaryText: NSColor(white: 0.32, alpha: 1.0),
        barBackground: NSColor(white: 0.92, alpha: 1.0),
        accent: NSColor.systemBlue,
        separatorColor: NSColor(white: 0.0, alpha: 0.35)
    )

    static let nord = Theme(
        name: "Nord",
        displayName: "Nord 极夜",
        primaryText: NSColor(hex: "#ECEFF4"),
        secondaryText: NSColor(hex: "#D8DEE9"),
        barBackground: NSColor(hex: "#2E3440"),
        accent: NSColor(hex: "#88C0D0"),
        separatorColor: NSColor(hex: "#4C566A")
    )

    static let dracula = Theme(
        name: "Dracula",
        displayName: "Dracula",
        primaryText: NSColor(hex: "#F8F8F2"),
        secondaryText: NSColor(hex: "#BABABA"),
        barBackground: NSColor(hex: "#282A36"),
        accent: NSColor(hex: "#BD93F9"),
        separatorColor: NSColor(hex: "#44475A")
    )

    static let solarizedDark = Theme(
        name: "SolarizedDark",
        displayName: "Solarized Dark",
        primaryText: NSColor(hex: "#EEE8D5"),
        secondaryText: NSColor(hex: "#93A1A1"),
        barBackground: NSColor(hex: "#002B36"),
        accent: NSColor(hex: "#268BD2"),
        separatorColor: NSColor(hex: "#073642")
    )

    static let tokyoNight = Theme(
        name: "TokyoNight",
        displayName: "Tokyo Night",
        primaryText: NSColor(hex: "#C0CAF5"),
        secondaryText: NSColor(hex: "#A9B1D6"),
        barBackground: NSColor(hex: "#1A1B26"),
        accent: NSColor(hex: "#7AA2F7"),
        separatorColor: NSColor(hex: "#414868")
    )

    static let gruvbox = Theme(
        name: "Gruvbox",
        displayName: "Gruvbox",
        primaryText: NSColor(hex: "#EBDBB2"),
        secondaryText: NSColor(hex: "#D5C4A1"),
        barBackground: NSColor(hex: "#282828"),
        accent: NSColor(hex: "#FE8019"),
        separatorColor: NSColor(hex: "#504945")
    )

    static let rosePine = Theme(
        name: "RosePine",
        displayName: "Rosé Pine",
        primaryText: NSColor(hex: "#E0DEF4"),
        secondaryText: NSColor(hex: "#CAC9DD"),
        barBackground: NSColor(hex: "#191724"),
        accent: NSColor(hex: "#C4A7E7"),
        separatorColor: NSColor(hex: "#403D52")
    )

    static let sunset = Theme(
        name: "Sunset",
        displayName: "Sunset",
        primaryText: NSColor(hex: "#FEF3C7"),
        secondaryText: NSColor(hex: "#FDE68A"),
        barBackground: NSColor(hex: "#D97706"),
        accent: NSColor(hex: "#FCD34D"),
        separatorColor: NSColor(hex: "#92400E")
    )

    static let ocean = Theme(
        name: "Ocean",
        displayName: "Ocean",
        primaryText: NSColor(hex: "#67E8F9"),
        secondaryText: NSColor(hex: "#A5F3FC"),
        barBackground: NSColor(hex: "#0E7490"),
        accent: NSColor(hex: "#06B6D4"),
        separatorColor: NSColor(hex: "#155E75")
    )

    static let forest = Theme(
        name: "Forest",
        displayName: "Forest",
        primaryText: NSColor(hex: "#BBF7D0"),
        secondaryText: NSColor(hex: "#86EFAC"),
        barBackground: NSColor(hex: "#14532D"),
        accent: NSColor(hex: "#22C55E"),
        separatorColor: NSColor(hex: "#166534")
    )

    static let bubblegum = Theme(
        name: "Bubblegum",
        displayName: "Bubblegum",
        primaryText: NSColor(hex: "#831843"),
        secondaryText: NSColor(hex: "#BE185D"),
        barBackground: NSColor(hex: "#FBCFE8"),
        accent: NSColor(hex: "#EC4899"),
        separatorColor: NSColor(hex: "#F9A8D4")
    )

    static let synthwave = Theme(
        name: "Synthwave",
        displayName: "Synthwave",
        primaryText: NSColor(hex: "#F0ABFC"),
        secondaryText: NSColor(hex: "#E5C6FF"),
        barBackground: NSColor(hex: "#2D1B69"),
        accent: NSColor(hex: "#FF00FF"),
        separatorColor: NSColor(hex: "#5B21B6")
    )

    static let crimson = Theme(
        name: "Crimson",
        displayName: "Crimson",
        primaryText: NSColor(hex: "#FECACA"),
        secondaryText: NSColor(hex: "#FCA5A5"),
        barBackground: NSColor(hex: "#7F1D1D"),
        accent: NSColor(hex: "#EF4444"),
        separatorColor: NSColor(hex: "#991B1B")
    )

    static var all: [Theme] {
        [dark, light, nord, dracula, solarizedDark, tokyoNight, gruvbox, rosePine,
         sunset, ocean, forest, bubblegum, synthwave, crimson]
    }

    static func current() -> Theme {
        let stored = PreferenceStore.shared.themeName
        return all.first(where: { $0.name == stored }) ?? dark
    }
}
