// 搜索服务提供商列表：增删改查
import UIKit

final class SearchProviderListViewController: UITableViewController {

    private var providers: [SearchProvider] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        applyLocalization()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self, action: #selector(addProvider))
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
        title = L("搜索服务", "Search Services")
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
        providers = SettingsStore.shared.searchProviders
        tableView.reloadData()
    }

    // MARK: - DataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        providers.isEmpty ? 1 : providers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        cell.backgroundColor = .agCellBackground
        let selView = UIView(); selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView

        if providers.isEmpty {
            cell.textLabel?.text = L("暂无搜索服务", "No search services yet")
            cell.textLabel?.textColor = UIColor.themed(
                light: UIColor(white: 0.50, alpha: 1),
                dark:  UIColor(white: 0.50, alpha: 1))
            cell.detailTextLabel?.text = L("点击 + 添加", "Tap + to add")
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let sp = providers[indexPath.row]
            cell.textLabel?.text = sp.displayName
            cell.textLabel?.textColor = .agTextBot
            cell.detailTextLabel?.text = L("\(sp.type.displayName) · 最多 \(sp.maxResults) 条",
                                           "\(sp.type.displayName) · up to \(sp.maxResults) results")
            cell.detailTextLabel?.textColor = UIColor.themed(
                light: UIColor(white: 0.45, alpha: 1),
                dark:  UIColor(white: 0.55, alpha: 1))
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !providers.isEmpty
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let id = providers[indexPath.row].id
        SettingsStore.shared.deleteSearchProvider(id: id)
        providers.remove(at: indexPath.row)
        if providers.isEmpty {
            tableView.reloadRows(at: [indexPath], with: .automatic)
        } else {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !providers.isEmpty else { return }
        let sp = providers[indexPath.row]
        let vc = SearchProviderEditViewController(provider: sp)
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Add

    @objc private func addProvider() {
        let sheet = UIAlertController(title: L("选择服务类型", "Choose Service Type"),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        for t in SearchProviderType.allCases {
            sheet.addAction(UIAlertAction(title: t.displayName, style: .default) { [weak self] _ in
                let sp = SearchProvider(type: t)
                let vc = SearchProviderEditViewController(provider: sp, isNew: true)
                self?.navigationController?.pushViewController(vc, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }
}
