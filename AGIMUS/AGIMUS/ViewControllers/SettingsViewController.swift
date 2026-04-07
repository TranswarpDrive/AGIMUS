// 设置页：Provider / 搜索服务 / 标题生成 / 默认 Prompt / 外观 / 清空历史 / 版本
import UIKit

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case providers, searchProviders, titleGen, defaults, appearance, data, about
        var title: String {
            switch self {
            case .providers:       return "聊天提供商"
            case .searchProviders: return "搜索服务"
            case .titleGen:        return "自动生成对话标题"
            case .defaults:        return "默认设置"
            case .appearance:      return "外观"
            case .data:            return "数据"
            case .about:           return "关于"
            }
        }
    }

    private var systemPrompt: String = SettingsStore.shared.defaultSystemPrompt
    private var titleProviderName: String = ""
    private var titleModelName: String    = ""

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 44
        NotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChange, object: nil)
        applyTheme()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        tableView.backgroundColor = .agBackground
        tableView.separatorColor  = .agSeparator
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        tableView.reloadData()
    }

    // 标题栏颜色随主题变化（含背景，防止切换模式后 header 残留浅色）
    override func tableView(_ tableView: UITableView,
                            willDisplayHeaderView view: UIView,
                            forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.40, alpha: 1),
            dark:  UIColor(white: 0.65, alpha: 1))
        let bgView = UIView()
        bgView.backgroundColor = .agBackground
        header.backgroundView = bgView
    }

    // 备注文字随主题变化（含背景）
    override func tableView(_ tableView: UITableView,
                            willDisplayFooterView view: UIView,
                            forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.font          = UIFont.systemFont(ofSize: 11)
        footer.textLabel?.textColor     = UIColor.themed(
            light: UIColor(white: 0.55, alpha: 1),
            dark:  UIColor(white: 0.45, alpha: 1))
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
        let p         = SettingsStore.shared.effectiveTitleProvider
        titleProviderName = p.name
        titleModelName    = SettingsStore.shared.effectiveTitleModel
    }

    // MARK: - DataSource
    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .providers:       return 1
        case .searchProviders: return 1
        case .titleGen:        return 2
        case .defaults:        return 1
        case .appearance:      return 1
        case .data:            return 1
        case .about:           return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .searchProviders: return "配置好搜索服务后，可在聊天界面工具栏选择启用。"
        case .titleGen:        return "首次问答结束后，自动调用所选模型总结并设置会话标题。"
        case .appearance:      return "iOS 13+ 使用系统级深色模式；iOS 12 使用内置自定义深色模式，两者均已支持。"
        default:               return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        cell.backgroundColor = .agCellBackground
        cell.textLabel?.textColor = .agTextBot
        cell.detailTextLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.45, alpha: 1),
            dark:  UIColor(white: 0.55, alpha: 1))
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator
        let selView = UIView()
        selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView

        switch Section(rawValue: indexPath.section)! {
        case .providers:
            let count  = SettingsStore.shared.providers.count
            let active = SettingsStore.shared.activeProvider.name
            cell.textLabel?.text = "管理提供商"
            cell.detailTextLabel?.text = "\(active)（共 \(count) 个）"

        case .searchProviders:
            let count = SettingsStore.shared.searchProviders.count
            cell.textLabel?.text = "管理搜索服务"
            cell.detailTextLabel?.text = count > 0 ? "共 \(count) 个" : "未配置"

        case .titleGen:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "提供商"
                cell.detailTextLabel?.text = titleProviderName
            default:
                cell.textLabel?.text = "模型"
                cell.detailTextLabel?.text = titleModelName
            }

        case .defaults:
            cell.textLabel?.text = "默认 System Prompt"
            cell.detailTextLabel?.text = String(systemPrompt.prefix(28))

        case .appearance:
            cell.textLabel?.text = "显示模式"
            let mode = SettingsStore.shared.appearanceMode
            switch mode {
            case 1:  cell.detailTextLabel?.text = "浅色"
            case 2:  cell.detailTextLabel?.text = "深色"
            default: cell.detailTextLabel?.text = "跟随系统"
            }

        case .data:
            cell.textLabel?.text = "清空所有会话"
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = .none

        case .about:
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let bld = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            cell.textLabel?.text = "版本"
            cell.detailTextLabel?.text = "\(ver) (\(bld))"
            cell.selectionStyle = .none
            cell.accessoryType = .none
        }
        return cell
    }

    // MARK: - Delegate
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

        case .data:
            confirmClear()

        case .about:
            break
        }
    }

    // MARK: - Title Provider / Model pickers

    private func pickTitleProvider() {
        let providers = SettingsStore.shared.providers
        let sheet = UIAlertController(title: "选择标题生成提供商", message: nil, preferredStyle: .actionSheet)
        for p in providers {
            let isCurrent = SettingsStore.shared.titleProviderID == p.id
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(p.name)" : p.name,
                                          style: .default) { [weak self] _ in
                SettingsStore.shared.titleProviderID = p.id
                SettingsStore.shared.titleModel = p.activeModel
                self?.refreshTitleConfig()
                self?.tableView.reloadSections(IndexSet(integer: Section.titleGen.rawValue), with: .none)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func pickTitleModel() {
        let p = SettingsStore.shared.effectiveTitleProvider
        guard !p.models.isEmpty else {
            let a = UIAlertController(title: "无可用模型", message: "请先在提供商中添加模型", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "好", style: .default))
            present(a, animated: true)
            return
        }
        let sheet = UIAlertController(title: "选择标题生成模型", message: nil, preferredStyle: .actionSheet)
        for m in p.models {
            let isCurrent = SettingsStore.shared.effectiveTitleModel == m
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(m)" : m,
                                          style: .default) { [weak self] _ in
                SettingsStore.shared.titleModel = m
                self?.refreshTitleConfig()
                self?.tableView.reloadSections(IndexSet(integer: Section.titleGen.rawValue), with: .none)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: - Appearance Picker

    private func pickAppearance() {
        let current = SettingsStore.shared.appearanceMode
        let sheet = UIAlertController(title: "选择显示模式", message: nil, preferredStyle: .actionSheet)

        let options: [(String, Int)] = [("跟随系统", 0), ("浅色", 1), ("深色", 2)]
        for (name, mode) in options {
            let isCurrent = current == mode
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(name)" : name,
                                          style: .default) { [weak self] _ in
                guard let self = self else { return }
                // ThemeManager 统一处理 iOS 12 和 13+ 两套机制（会发送通知，applyTheme 会 reloadData）
                ThemeManager.shared.apply(mode: mode, to: self.view.window)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: - Editors

    private func editSystemPrompt() {
        let a = UIAlertController(title: "默认 System Prompt", message: nil, preferredStyle: .alert)
        a.addTextField { [weak self] tf in
            tf.text = self?.systemPrompt
            tf.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.systemPrompt = a.textFields?.first?.text ?? ""
            self.tableView.reloadSections(IndexSet(integer: Section.defaults.rawValue), with: .none)
        })
        present(a, animated: true)
    }

    private func confirmClear() {
        let a = UIAlertController(title: "清空所有会话", message: "此操作不可撤销", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "清空", style: .destructive) { _ in
            SessionStore.shared.clearAll()
        })
        present(a, animated: true)
    }
}
