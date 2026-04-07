// 提供商列表：新建 / 选择激活 / 编辑 / 删除
import UIKit

final class ProviderListViewController: UITableViewController {

    private var providers: [ProviderConfig] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        applyLocalization()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self,
                                                            action: #selector(addProvider))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .appLanguageDidChange, object: nil)
        applyTheme()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() { applyTheme() }
    @objc private func languageChanged() {
        applyLocalization()
        tableView.reloadData()
    }

    private func applyLocalization() {
        title = L("提供商管理", "Providers")
    }

    private func applyTheme() {
        tableView.backgroundColor = .agBackground
        tableView.separatorColor  = .agSeparator
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        reload()
    }

    private func reload() {
        providers = SettingsStore.shared.providers
        tableView.reloadData()
    }

    // MARK: - DataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        providers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        let p = providers[indexPath.row]
        cell.textLabel?.text = p.displayName
        cell.detailTextLabel?.text = "\(p.activeModel)  |  \(p.baseURL)"
        cell.detailTextLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.45, alpha: 1),
            dark:  UIColor(white: 0.55, alpha: 1))
        cell.backgroundColor = .agCellBackground
        let selView = UIView(); selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView
        // Checkmark for active provider
        let isActive = p.id == SettingsStore.shared.activeProviderID
        cell.accessoryType = isActive ? .checkmark : .disclosureIndicator
        cell.textLabel?.textColor = isActive ? UIColor.agBubbleUser : .agTextBot
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }

    // MARK: - Delegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let p = providers[indexPath.row]
        let isActive = p.id == SettingsStore.shared.activeProviderID

        if isActive {
            // Already active → go to edit
            let vc = ProviderEditViewController(provider: p)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            // Not active → show action: select or edit
            let sheet = UIAlertController(title: p.displayName, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: L("设为当前提供商", "Set as Active Provider"), style: .default) { [weak self] _ in
                SettingsStore.shared.activeProviderID = p.id
                self?.reload()
            })
            sheet.addAction(UIAlertAction(title: L("编辑", "Edit"), style: .default) { [weak self] _ in
                let vc = ProviderEditViewController(provider: p)
                self?.navigationController?.pushViewController(vc, animated: true)
            })
            sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
            present(sheet, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let p = providers[indexPath.row]
        SettingsStore.shared.deleteProvider(id: p.id)
        providers = SettingsStore.shared.providers
        tableView.reloadData()
    }

    // MARK: - Add
    @objc private func addProvider() {
        let vc = ProviderEditViewController(provider: ProviderConfig(), isNew: true)
        navigationController?.pushViewController(vc, animated: true)
    }
}
