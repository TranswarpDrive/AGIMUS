// 主题管理：iOS 12 自定义深色模式 + iOS 13+ overrideUserInterfaceStyle 并行
import UIKit

final class ThemeManager {
    static let shared = ThemeManager()

    /// 所有订阅者监听此通知来刷新颜色（iOS 12 和 13+ 均会发送）
    static let didChange = Notification.Name("ThemeManagerDidChange")

    private init() {}

    // MARK: - Query

    var isDark: Bool {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.windows.first?.traitCollection.userInterfaceStyle == .dark
        }
        return SettingsStore.shared.appearanceMode == 2
    }

    // MARK: - Apply

    func apply(mode: Int, to window: UIWindow?) {
        SettingsStore.shared.appearanceMode = mode
        if #available(iOS 13.0, *) {
            let style: UIUserInterfaceStyle = mode == 1 ? .light : mode == 2 ? .dark : .unspecified
            window?.overrideUserInterfaceStyle = style
        }
        // UINavigationBar.appearance() 更改仅影响新建实例，因此同时更新所有已存在的 bar
        refreshAllNavigationBars()
        NotificationCenter.default.post(name: ThemeManager.didChange, object: nil)
    }

    // MARK: - Navigation bar helpers

    /// 更新单条导航栏的外观（iOS 12 需要手动更新 CGColor / barTintColor）
    func styleNavigationBar(_ bar: UINavigationBar?) {
        guard let bar = bar else { return }
        if isDark {
            let bg = UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
            let fg = UIColor(white: 0.92, alpha: 1)
            let accent = UIColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 1)
            bar.barTintColor = bg
            bar.tintColor    = accent
            bar.titleTextAttributes = [.foregroundColor: fg]
            if #available(iOS 11.0, *) {
                bar.largeTitleTextAttributes = [.foregroundColor: fg]
            }
            // 保持 translucent = true，避免改变 ViewController view 的布局 frame
            // （non-translucent 导致 view.bounds.height 小于屏幕高度，键盘偏移量计算错误）
        } else {
            bar.barTintColor = nil     // 恢复系统默认
            bar.tintColor    = nil
            bar.titleTextAttributes = nil
            if #available(iOS 11.0, *) {
                bar.largeTitleTextAttributes = nil
            }
        }
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
    }

    // MARK: - Private

    /// 遍历所有 window → 所有 navigationController，批量更新已存在的导航栏
    private func refreshAllNavigationBars() {
        UIApplication.shared.windows.forEach { window in
            func walk(_ vc: UIViewController?) {
                guard let vc = vc else { return }
                if let nav = vc as? UINavigationController {
                    styleNavigationBar(nav.navigationBar)
                } else if let nav = vc.navigationController {
                    styleNavigationBar(nav.navigationBar)
                }
                vc.children.forEach { walk($0) }
                vc.presentedViewController.map { walk($0) }
            }
            walk(window.rootViewController)
        }
    }
}
