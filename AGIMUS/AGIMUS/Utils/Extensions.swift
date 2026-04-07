// UIKit 公共扩展：颜色常量（支持 iOS 12 自定义深色模式 + iOS 13+ Dynamic Color）
import UIKit

// MARK: - Semantic Color Palette

extension UIColor {

    // ── 工具方法 ──────────────────────────────────────────────────────
    /// 返回一个在深色/浅色模式下自动切换的颜色。
    /// iOS 13+：使用 UIColor(dynamicProvider:)，由系统 traitCollection 驱动；
    /// iOS 12  ：直接查询 ThemeManager.shared.isDark，静态返回当前颜色
    ///           （切换时通过 ThemeManager.didChange 通知由视图主动刷新）。
    static func themed(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        }
        return ThemeManager.shared.isDark ? dark : light
    }

    // ── App 背景 ──────────────────────────────────────────────────────
    static var agBackground: UIColor {
        themed(light: UIColor(white: 0.97, alpha: 1),
               dark:  UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    }
    static var agNavBar: UIColor {
        themed(light: UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1),
               dark:  UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    }
    static var agSeparator: UIColor {
        themed(light: UIColor(white: 0.82, alpha: 1),
               dark:  UIColor(white: 0.22, alpha: 1))
    }

    // ── 聊天气泡（旧式 bubble 设计保留，chatroom 模式用 agCellXxx） ──
    static var agBubbleUser: UIColor {
        themed(light: UIColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 1),
               dark:  UIColor(red: 0.10, green: 0.38, blue: 0.86, alpha: 1))
    }
    static var agBubbleBot: UIColor {
        themed(light: UIColor(white: 0.93, alpha: 1),
               dark:  UIColor(red: 0.172, green: 0.172, blue: 0.180, alpha: 1))
    }
    static var agBubbleError: UIColor {
        themed(light: UIColor(red: 1.0, green: 0.93, blue: 0.93, alpha: 1),
               dark:  UIColor(red: 0.28, green: 0.08, blue: 0.08, alpha: 1))
    }

    // ── 文字 ──────────────────────────────────────────────────────────
    static var agTextUser: UIColor { UIColor.white }
    static var agTextBot: UIColor {
        themed(light: UIColor(white: 0.10, alpha: 1),
               dark:  UIColor(white: 0.92, alpha: 1))
    }

    // ── 代码块 ───────────────────────────────────────────────────────
    static var agCodeBG: UIColor {
        themed(light: UIColor(white: 0.88, alpha: 1),
               dark:  UIColor(red: 0.172, green: 0.172, blue: 0.180, alpha: 1))
    }
    static var agCodeText: UIColor {
        themed(light: UIColor(red: 0.15, green: 0.35, blue: 0.55, alpha: 1),
               dark:  UIColor(red: 0.47, green: 0.70, blue: 0.83, alpha: 1))
    }

    // ── Chatroom 消息行专用背景 ───────────────────────────────────────
    /// 用户消息行背景
    static var agCellUser: UIColor {
        themed(light: UIColor(red: 0.94, green: 0.96, blue: 1.00, alpha: 1),
               dark:  UIColor(red: 0.12, green: 0.14, blue: 0.24, alpha: 1))
    }
    /// AI 消息行背景
    static var agCellBot: UIColor {
        themed(light: UIColor(white: 1.0, alpha: 1),
               dark:  UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    }
    /// 通用表格 cell 背景（设置页等）
    /// 深色：比页面背景 #1C1C1E 亮一档，形成可见层次感，但不像浅色模式那样与背景形成强对比
    static var agCellBackground: UIColor {
        themed(light: UIColor.white,
               dark:  UIColor(red: 0.168, green: 0.168, blue: 0.178, alpha: 1))
    }
    /// cell 点击高亮色：选中时比常规状态再亮一档，给出清晰点击反馈
    static var agCellSelection: UIColor {
        themed(light: UIColor(white: 0.90, alpha: 1),
               dark:  UIColor(red: 0.272, green: 0.272, blue: 0.290, alpha: 1))
    }

    // ── 输入栏 / 工具栏 ───────────────────────────────────────────────
    static var agInputBackground: UIColor {
        themed(light: UIColor.white,
               dark:  UIColor(red: 0.172, green: 0.172, blue: 0.180, alpha: 1))
    }
    static var agToolbarBackground: UIColor {
        themed(light: UIColor(white: 0.97, alpha: 1),
               dark:  UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    }

    // ── 思考视图 ──────────────────────────────────────────────────────
    static var agThinkingBackground: UIColor {
        themed(light: UIColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 1),
               dark:  UIColor(red: 0.15, green: 0.18, blue: 0.28, alpha: 1))
    }
    static var agThinkingBorder: UIColor {
        themed(light: UIColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 1),
               dark:  UIColor(red: 0.3, green: 0.38, blue: 0.58, alpha: 1))
    }
    static var agThinkingText: UIColor {
        themed(light: UIColor(red: 0.3, green: 0.4, blue: 0.55, alpha: 1),
               dark:  UIColor(red: 0.55, green: 0.70, blue: 0.85, alpha: 1))
    }
    static var agThinkingHeader: UIColor {
        themed(light: UIColor(red: 0.35, green: 0.45, blue: 0.65, alpha: 1),
               dark:  UIColor(red: 0.55, green: 0.68, blue: 0.88, alpha: 1))
    }
}

// MARK: - View helpers

extension UIView {
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }

    func pinEdges(to guide: UILayoutGuide, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

// MARK: - Font helpers

extension UIFont {
    static func monospacedBody(size: CGFloat = 13) -> UIFont {
        UIFont(name: "Menlo", size: size) ?? UIFont.systemFont(ofSize: size)
    }
}
