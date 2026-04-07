import UIKit

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case providers, searchProviders, titleGen, defaults, appearance, language, data, about

        var title: String {
            switch self {
            case .providers:       return L("聊天提供商", "Chat Providers")
            case .searchProviders: return L("搜索服务", "Search Services")
            case .titleGen:        return L("自动生成对话标题", "Auto Title Generation")
            case .defaults:        return L("默认设置", "Defaults")
            case .appearance:      return L("外观", "Appearance")
            case .language:        return L("语言", "Language")
            case .data:            return L("数据", "Data")
            case .about:           return L("关于", "About")
            }
        }
    }

    private var systemPrompt: String = SettingsStore.shared.defaultSystemPrompt
    private var titleProviderName: String = ""
    private var titleModelName: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        applyLocalization()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 44

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeChanged),
                                               name: ThemeManager.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(languageChanged),
                                               name: .appLanguageDidChange,
                                               object: nil)
        applyTheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    @objc private func languageChanged() {
        applyLocalization()
        refreshTitleConfig()
        tableView.reloadData()
    }

    private func applyLocalization() {
        title = L("设置", "Settings")
    }

    private func applyTheme() {
        tableView.backgroundColor = .agBackground
        tableView.separatorColor = .agSeparator
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView,
                            willDisplayHeaderView view: UIView,
                            forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.40, alpha: 1),
            dark: UIColor(white: 0.65, alpha: 1)
        )
        let bgView = UIView()
        bgView.backgroundColor = .agBackground
        header.backgroundView = bgView
    }

    override func tableView(_ tableView: UITableView,
                            willDisplayFooterView view: UIView,
                            forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.font = UIFont.systemFont(ofSize: 11)
        footer.textLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.55, alpha: 1),
            dark: UIColor(white: 0.45, alpha: 1)
        )
        footer.textLabel?.numberOfLines = 0
        let bgView = UIView()
        bgView.backgroundColor = .agBackground
        footer.backgroundView = bgView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTitleConfig()
        applyTheme()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SettingsStore.shared.defaultSystemPrompt = systemPrompt
    }

    private func refreshTitleConfig() {
        let provider = SettingsStore.shared.effectiveTitleProvider
        titleProviderName = provider.displayName
        titleModelName = SettingsStore.shared.effectiveTitleModel
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .providers:       return 1
        case .searchProviders: return 1
        case .titleGen:        return 2
        case .defaults:        return 1
        case .appearance:      return 1
        case .language:        return 1
        case .data:            return 1
        case .about:           return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .searchProviders:
            return L("配置好搜索服务后，可在聊天界面工具栏选择启用。",
                     "After configuring search services, you can enable them in the chat toolbar.")
        case .titleGen:
            return L("首次问答结束后，自动调用所选模型总结并设置会话标题。",
                     "After the first completed exchange, the selected model can summarize and set the chat title.")
        case .appearance:
            return L("iOS 13+ 使用系统级深色模式；iOS 12 使用内置自定义深色模式，两者均已支持。",
                     "On iOS 13+, the app follows system appearance. On iOS 12, it uses built-in dark mode.")
        case .language:
            return L("切换应用内界面文案语言。",
                     "Switch UI language for in-app text.")
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        cell.backgroundColor = .agCellBackground
        cell.textLabel?.textColor = .agTextBot
        cell.detailTextLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.45, alpha: 1),
            dark: UIColor(white: 0.55, alpha: 1)
        )
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator
        let selView = UIView()
        selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView

        switch Section(rawValue: indexPath.section)! {
        case .providers:
            let count = SettingsStore.shared.providers.count
            let active = SettingsStore.shared.activeProvider.displayName
            cell.textLabel?.text = L("管理提供商", "Manage Providers")
            cell.detailTextLabel?.text = L("\(active)（共 \(count) 个）", "\(active) (\(count) total)")

        case .searchProviders:
            let count = SettingsStore.shared.searchProviders.count
            cell.textLabel?.text = L("管理搜索服务", "Manage Search Services")
            cell.detailTextLabel?.text = count > 0 ? L("共 \(count) 个", "\(count) total")
                                                   : L("未配置", "Not configured")

        case .titleGen:
            if indexPath.row == 0 {
                cell.textLabel?.text = L("提供商", "Provider")
                cell.detailTextLabel?.text = titleProviderName
            } else {
                cell.textLabel?.text = L("模型", "Model")
                cell.detailTextLabel?.text = titleModelName
            }

        case .defaults:
            cell.textLabel?.text = L("默认 System Prompt", "Default System Prompt")
            cell.detailTextLabel?.text = String(systemPrompt.prefix(28))

        case .appearance:
            cell.textLabel?.text = L("显示模式", "Display Mode")
            switch SettingsStore.shared.appearanceMode {
            case 1: cell.detailTextLabel?.text = L("浅色", "Light")
            case 2: cell.detailTextLabel?.text = L("深色", "Dark")
            default: cell.detailTextLabel?.text = L("跟随系统", "System")
            }

        case .language:
            cell.textLabel?.text = L("应用语言", "App Language")
            cell.detailTextLabel?.text = SettingsStore.shared.appLanguage.optionLabel

        case .data:
            cell.textLabel?.text = L("清空所有会话", "Clear All Sessions")
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = .none

        case .about:
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let bld = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            cell.textLabel?.text = L("版本", "Version")
            cell.detailTextLabel?.text = "\(ver) (\(bld))"
            cell.selectionStyle = .none
            cell.accessoryType = .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .providers:
            navigationController?.pushViewController(ProviderListViewController(), animated: true)
        case .searchProviders:
            navigationController?.pushViewController(SearchProviderListViewController(), animated: true)
        case .titleGen:
            indexPath.row == 0 ? pickTitleProvider() : pickTitleModel()
        case .defaults:
            editSystemPrompt()
        case .appearance:
            pickAppearance()
        case .language:
            pickLanguage()
        case .data:
            confirmClear()
        case .about:
            break
        }
    }

    private func pickTitleProvider() {
        let providers = SettingsStore.shared.providers
        let sheet = UIAlertController(title: L("选择标题生成提供商", "Choose Title Provider"),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        for provider in providers {
            let isCurrent = SettingsStore.shared.titleProviderID == provider.id
            let name = provider.displayName
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(name)" : name, style: .default) { [weak self] _ in
                SettingsStore.shared.titleProviderID = provider.id
                SettingsStore.shared.titleModel = provider.activeModel
                self?.refreshTitleConfig()
                self?.tableView.reloadSections(IndexSet(integer: Section.titleGen.rawValue), with: .none)
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func pickTitleModel() {
        let provider = SettingsStore.shared.effectiveTitleProvider
        guard !provider.models.isEmpty else {
            let a = UIAlertController(title: L("无可用模型", "No Models Available"),
                                      message: L("请先在提供商中添加模型", "Please add a model to a provider first."),
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
            present(a, animated: true)
            return
        }

        let sheet = UIAlertController(title: L("选择标题生成模型", "Choose Title Model"),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        for model in provider.models {
            let isCurrent = SettingsStore.shared.effectiveTitleModel == model
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(model)" : model,
                                          style: .default) { [weak self] _ in
                SettingsStore.shared.titleModel = model
                self?.refreshTitleConfig()
                self?.tableView.reloadSections(IndexSet(integer: Section.titleGen.rawValue), with: .none)
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func pickAppearance() {
        let current = SettingsStore.shared.appearanceMode
        let sheet = UIAlertController(title: L("选择显示模式", "Choose Display Mode"),
                                      message: nil,
                                      preferredStyle: .actionSheet)

        let options: [(String, Int)] = [
            (L("跟随系统", "System"), 0),
            (L("浅色", "Light"), 1),
            (L("深色", "Dark"), 2)
        ]
        for (name, mode) in options {
            let isCurrent = current == mode
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(name)" : name, style: .default) { [weak self] _ in
                guard let self = self else { return }
                ThemeManager.shared.apply(mode: mode, to: self.view.window)
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func pickLanguage() {
        let current = SettingsStore.shared.appLanguage
        let sheet = UIAlertController(title: L("选择语言", "Choose Language"),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        for language in AppLanguage.allCases {
            let title = language.optionLabel
            let isCurrent = language == current
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(title)" : title,
                                          style: .default) { [weak self] _ in
                SettingsStore.shared.appLanguage = language
                self?.applyLocalization()
                self?.refreshTitleConfig()
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func editSystemPrompt() {
        let a = UIAlertController(title: L("默认 System Prompt", "Default System Prompt"),
                                  message: nil,
                                  preferredStyle: .alert)
        a.addTextField { [weak self] tf in
            tf.text = self?.systemPrompt
            tf.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.systemPrompt = a.textFields?.first?.text ?? ""
            self.tableView.reloadSections(IndexSet(integer: Section.defaults.rawValue), with: .none)
        })
        present(a, animated: true)
    }

    private func confirmClear() {
        let a = UIAlertController(title: L("清空所有会话", "Clear All Sessions"),
                                  message: L("此操作不可撤销", "This action cannot be undone."),
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("清空", "Clear"), style: .destructive) { _ in
            SessionStore.shared.clearAll()
        })
        present(a, animated: true)
    }
}
