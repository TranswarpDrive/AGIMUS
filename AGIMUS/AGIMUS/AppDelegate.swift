// App 入口：传统 window-based 生命周期，兼容 iOS 12
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        let sessionListVC = SessionListViewController()
        let nav = UINavigationController(rootViewController: sessionListVC)
        nav.navigationBar.prefersLargeTitles = true

        window?.rootViewController = nav
        window?.makeKeyAndVisible()

        // 恢复上次保存的外观模式（iOS 12 自定义深色模式 + iOS 13+ 系统级深色模式）
        let mode = SettingsStore.shared.appearanceMode
        if #available(iOS 13.0, *) {
            let style: UIUserInterfaceStyle = mode == 1 ? .light : mode == 2 ? .dark : .unspecified
            window?.overrideUserInterfaceStyle = style
        }
        // 启动时立即为导航栏设置正确颜色（视图首次出现前应用，iOS 12 和 13+ 均需要）
        ThemeManager.shared.styleNavigationBar(nav.navigationBar)

        return true
    }
}
