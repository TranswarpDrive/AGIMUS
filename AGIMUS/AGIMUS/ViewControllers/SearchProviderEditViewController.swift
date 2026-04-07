// 搜索服务提供商编辑页：名称 / 类型 / 端点 / API Key / 最多返回条数
import UIKit

final class SearchProviderEditViewController: UITableViewController {

    private var provider: SearchProvider
    private let isNew: Bool

    private enum Row: Int, CaseIterable {
        case name, type, endpoint, apiKey, maxResults
        var label: String {
            switch self {
            case .name:       return L("名称", "Name")
            case .type:       return L("服务类型", "Service Type")
            case .endpoint:   return L("API 端点", "API Endpoint")
            case .apiKey:     return "API Key"
            case .maxResults: return L("最多返回条数", "Max Results")
            }
        }
    }

    // MARK: - Init

    init(provider: SearchProvider, isNew: Bool = false) {
        self.provider = provider
        self.isNew    = isNew
        super.init(style: .grouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyLocalization()
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("保存", "Save"), style: .done,
                                                            target: self, action: #selector(save))
        if !isNew {
            let del = UIBarButtonItem(title: L("删除", "Delete"), style: .plain, target: self, action: #selector(deleteProvider))
            del.tintColor = UIColor.systemRed
            navigationItem.leftBarButtonItem = del
        }
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
        title = isNew ? L("添加搜索服务", "Add Search Service")
                      : L("编辑搜索服务", "Edit Search Service")
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
    }

    // MARK: - DataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        cell.backgroundColor = .agCellBackground
        cell.textLabel?.textColor = .agTextBot
        cell.detailTextLabel?.textColor = UIColor.themed(
            light: UIColor(white: 0.45, alpha: 1),
            dark:  UIColor(white: 0.55, alpha: 1))
        let selView = UIView(); selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView
        let row = Row(rawValue: indexPath.row)!
        cell.textLabel?.text = row.label

        switch row {
        case .name:
            cell.detailTextLabel?.text = provider.displayName
            cell.accessoryType = .disclosureIndicator
        case .type:
            cell.detailTextLabel?.text = provider.type.displayName
            cell.accessoryType = .disclosureIndicator
        case .endpoint:
            let ep = provider.endpoint.isEmpty ? L("（使用默认）", "(Use default)") : provider.endpoint
            cell.detailTextLabel?.text = ep.count > 30 ? "…" + ep.suffix(28) : ep
            cell.accessoryType = .disclosureIndicator
        case .apiKey:
            let key = SettingsStore.shared.searchAPIKey(for: provider.id)
            cell.detailTextLabel?.text = key.isEmpty ? L("未设置", "Not set") : "••••••••"
            cell.accessoryType = .disclosureIndicator
            if !provider.type.needsAPIKey {
                cell.textLabel?.textColor = UIColor.themed(
                    light: UIColor(white: 0.55, alpha: 1),
                    dark:  UIColor(white: 0.45, alpha: 1))
                cell.detailTextLabel?.text = L("不需要", "Not required")
                cell.selectionStyle = .none
                cell.accessoryType = .none
            }
        case .maxResults:
            cell.detailTextLabel?.text = "\(provider.maxResults)"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Row(rawValue: indexPath.row)! {
        case .name:       editName()
        case .type:       pickType()
        case .endpoint:   editEndpoint()
        case .apiKey:
            guard provider.type.needsAPIKey else { return }
            editAPIKey()
        case .maxResults: editMaxResults()
        }
    }

    // MARK: - Field editors

    private func editName() {
        let a = UIAlertController(title: L("名称", "Name"), message: nil, preferredStyle: .alert)
        a.addTextField { [weak self] tf in tf.text = self?.provider.name }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }
            self.provider.name = text
            self.tableView.reloadData()
        })
        present(a, animated: true)
    }

    private func pickType() {
        let sheet = UIAlertController(title: L("选择服务类型", "Choose Service Type"),
                                      message: nil,
                                      preferredStyle: .actionSheet)
        for t in SearchProviderType.allCases {
            let isCurrent = t == provider.type
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(t.displayName)" : t.displayName,
                                          style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.provider.type = t
                if t.legacyDisplayNames.contains(self.provider.name) {
                    self.provider.name = t.displayName
                }
                self.provider.endpoint = t.defaultEndpoint
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func editEndpoint() {
        let a = UIAlertController(title: L("API 端点", "API Endpoint"),
                                  message: L("留空使用默认值", "Leave empty to use default."),
                                  preferredStyle: .alert)
        a.addTextField { [weak self] tf in
            tf.text = self?.provider.endpoint
            tf.placeholder = self?.provider.type.defaultEndpoint
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let text = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            self.provider.endpoint = text.isEmpty ? self.provider.type.defaultEndpoint : text
            self.tableView.reloadData()
        })
        present(a, animated: true)
    }

    private func editAPIKey() {
        let current = SettingsStore.shared.searchAPIKey(for: provider.id)
        let a = UIAlertController(title: "API Key", message: nil, preferredStyle: .alert)
        a.addTextField { tf in
            tf.text = current
            tf.isSecureTextEntry = true
            tf.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let key = a.textFields?.first?.text ?? ""
            SettingsStore.shared.setSearchAPIKey(key, for: self.provider.id)
            self.tableView.reloadData()
        })
        present(a, animated: true)
    }

    private func editMaxResults() {
        let a = UIAlertController(title: L("最多返回条数", "Max Results"),
                                  message: L("建议 3-10", "Recommended: 3-10"),
                                  preferredStyle: .alert)
        a.addTextField { [weak self] tf in
            tf.text = "\(self?.provider.maxResults ?? 5)"
            tf.keyboardType = .numberPad
        }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = a.textFields?.first?.text,
                  let n = Int(text), n > 0 else { return }
            self.provider.maxResults = min(n, 20)
            self.tableView.reloadData()
        })
        present(a, animated: true)
    }

    // MARK: - Save / Delete

    @objc private func save() {
        SettingsStore.shared.updateSearchProvider(provider)
        navigationController?.popViewController(animated: true)
    }

    @objc private func deleteProvider() {
        let a = UIAlertController(title: L("删除搜索服务", "Delete Search Service"),
                                  message: L("此操作不可撤销", "This action cannot be undone."),
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("删除", "Delete"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            SettingsStore.shared.deleteSearchProvider(id: self.provider.id)
            self.navigationController?.popViewController(animated: true)
        })
        present(a, animated: true)
    }
}
