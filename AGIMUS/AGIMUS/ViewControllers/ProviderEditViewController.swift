// 提供商编辑页：基本信息 / 推理参数 / 模型列表管理（含 API 拉取）
import UIKit

final class ProviderEditViewController: UITableViewController {

    private var provider: ProviderConfig
    private var apiKey: String
    private let isNew: Bool

    // MARK: - Init
    init(provider: ProviderConfig, isNew: Bool = false) {
        self.provider = provider
        self.apiKey   = SettingsStore.shared.apiKey(for: provider.id)
        self.isNew    = isNew
        super.init(style: .grouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Sections
    private enum Section: Int, CaseIterable {
        case basic, params, models
        var title: String {
            switch self {
            case .basic:   return "基本信息"
            case .params:  return "推理参数"
            case .models:  return "模型列表"
            }
        }
    }

    // Rows in each section
    private let basicRows  = ["名称", "Base URL", "API Key"]
    private let paramRows  = ["Temperature", "Max Tokens", "流式输出"]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "新建提供商" : "编辑提供商"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done,
                                                            target: self, action: #selector(save))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.keyboardDismissMode = .onDrag
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    // MARK: - Save
    @objc private func save() {
        // Validate
        let trimURL = provider.baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimURL.isEmpty, URL(string: trimURL) != nil else {
            alert("请填写有效的 Base URL"); return
        }
        provider.baseURL = trimURL
        if provider.models.isEmpty { provider.models = [provider.activeModel] }
        if !provider.models.contains(provider.activeModel) {
            provider.activeModel = provider.models.first ?? provider.activeModel
        }

        SettingsStore.shared.updateProvider(provider)
        SettingsStore.shared.setAPIKey(apiKey, for: provider.id)

        if isNew {
            // Auto-select if only provider
            if SettingsStore.shared.providers.count == 1 {
                SettingsStore.shared.activeProviderID = provider.id
            }
        }
        navigationController?.popViewController(animated: true)
    }

    // MARK: - DataSource
    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .basic:  return basicRows.count
        case .params: return paramRows.count
        case .models: return provider.models.count + 1  // +1 for "添加模型" row
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == Section.models.rawValue ? "0 = 不限制 Max Tokens；长按模型可设为当前使用" : nil
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == Section.models.rawValue else { return nil }
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 80))
        let label = UILabel(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 30))
        label.text = "0 = 不限制 Max Tokens；轻触模型名可设为当前使用的模型"
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .gray
        label.numberOfLines = 2
        footer.addSubview(label)

        let fetchBtn = UIButton(type: .system)
        fetchBtn.setTitle("⬇ 从 API 拉取模型列表", for: .normal)
        fetchBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        fetchBtn.frame = CGRect(x: 16, y: 38, width: 220, height: 32)
        fetchBtn.addTarget(self, action: #selector(fetchModels), for: .touchUpInside)
        footer.addSubview(fetchBtn)
        return footer
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == Section.models.rawValue ? 80 : UITableView.automaticDimension
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
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .basic:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "名称"
                cell.detailTextLabel?.text = provider.name
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Base URL"
                cell.detailTextLabel?.text = provider.baseURL
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "API Key"
                cell.detailTextLabel?.text = apiKey.isEmpty ? "未设置" : maskedKey(apiKey)
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case .params:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Temperature"
                cell.detailTextLabel?.text = String(format: "%.2f", provider.temperature)
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Max Tokens"
                cell.detailTextLabel?.text = provider.maxTokens == 0 ? "不限制" : "\(provider.maxTokens)"
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "流式输出"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = provider.useStream
                sw.tag = indexPath.row
                sw.addTarget(self, action: #selector(streamToggled(_:)), for: .valueChanged)
                cell.accessoryView = sw
            default: break
            }

        case .models:
            let addRow = provider.models.count
            if indexPath.row == addRow {
                cell.textLabel?.text = "➕ 手动添加模型…"
                cell.textLabel?.textColor = UIColor.agBubbleUser
            } else {
                let model = provider.models[indexPath.row]
                cell.textLabel?.text = model
                cell.textLabel?.textColor = .agTextBot
                let isActive = model == provider.activeModel
                cell.accessoryType = isActive ? .checkmark : .none
                cell.detailTextLabel?.text = isActive ? "当前" : nil
            }
        }
        return cell
    }

    // MARK: - Delegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .basic:
            switch indexPath.row {
            case 0: editText("提供商名称", current: provider.name, secure: false) {
                self.provider.name = $0; tableView.reloadRows(at: [indexPath], with: .none)
            }
            case 1: editText("Base URL", current: provider.baseURL, secure: false) {
                self.provider.baseURL = $0; tableView.reloadRows(at: [indexPath], with: .none)
            }
            case 2: editText("API Key", current: apiKey, secure: true) {
                self.apiKey = $0; tableView.reloadRows(at: [indexPath], with: .none)
            }
            default: break
            }

        case .params:
            switch indexPath.row {
            case 0:
                editNumber("Temperature (0.0 ~ 2.0)", current: String(format: "%.2f", provider.temperature)) {
                    if let v = Double($0), v >= 0 && v <= 2 { self.provider.temperature = v }
                    tableView.reloadRows(at: [indexPath], with: .none)
                }
            case 1:
                editNumber("Max Tokens（0 = 不限制）", current: "\(provider.maxTokens)") {
                    if let v = Int($0), v >= 0 { self.provider.maxTokens = v }
                    tableView.reloadRows(at: [indexPath], with: .none)
                }
            default: break
            }

        case .models:
            let addRow = provider.models.count
            if indexPath.row == addRow {
                addModelManually()
            } else {
                // Set as active model
                provider.activeModel = provider.models[indexPath.row]
                tableView.reloadSections(IndexSet(integer: Section.models.rawValue), with: .none)
            }
        }
    }

    // Swipe-to-delete on model rows only
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.models.rawValue && indexPath.row < provider.models.count
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              indexPath.section == Section.models.rawValue,
              indexPath.row < provider.models.count else { return }
        let removed = provider.models[indexPath.row]
        provider.models.remove(at: indexPath.row)
        if provider.activeModel == removed {
            provider.activeModel = provider.models.first ?? ""
        }
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    // MARK: - Actions

    @objc private func streamToggled(_ sw: UISwitch) {
        provider.useStream = sw.isOn
    }

    @objc private func fetchModels() {
        let trimURL = provider.baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimURL.isEmpty, URL(string: trimURL) != nil else {
            alert("请先填写有效的 Base URL"); return
        }
        let key = apiKey
        // Show loading
        let hud = makeHUD("拉取中…")
        view.addSubview(hud)

        ChatAPIService.shared.fetchModels(baseURL: trimURL, apiKey: key) { [weak self] result in
            hud.removeFromSuperview()
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                self.alert("拉取失败：\(err.localizedDescription)")
            case .success(let ids):
                if ids.isEmpty { self.alert("未返回任何模型"); return }
                self.showModelPicker(fetchedModels: ids)
            }
        }
    }

    private func addModelManually() {
        let a = UIAlertController(title: "添加模型", message: "输入模型名称", preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = "例如 gpt-4o"
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "添加", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            self.addModel(name)
        })
        present(a, animated: true)
    }

    private func showModelPicker(fetchedModels: [String]) {
        let vc = ModelPickerViewController(
            available: fetchedModels,
            alreadyAdded: provider.models
        ) { [weak self] selected in
            guard let self = self else { return }
            for m in selected where !self.provider.models.contains(m) {
                self.provider.models.append(m)
            }
            if self.provider.activeModel.isEmpty, let first = self.provider.models.first {
                self.provider.activeModel = first
            }
            self.tableView.reloadSections(IndexSet(integer: Section.models.rawValue), with: .automatic)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func addModel(_ name: String) {
        guard !provider.models.contains(name) else { return }
        provider.models.append(name)
        if provider.activeModel.isEmpty { provider.activeModel = name }
        let ip = IndexPath(row: provider.models.count - 1, section: Section.models.rawValue)
        tableView.insertRows(at: [ip], with: .automatic)
    }

    // MARK: - Helpers

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + String(repeating: "•", count: 8) + String(key.suffix(4))
    }

    private func editText(_ title: String, current: String, secure: Bool,
                          completion: @escaping (String) -> Void) {
        let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        a.addTextField { tf in
            tf.text = current
            tf.isSecureTextEntry = secure
            tf.clearButtonMode = .whileEditing
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            if let t = a.textFields?.first?.text { completion(t) }
        })
        present(a, animated: true)
    }

    private func editNumber(_ title: String, current: String,
                            completion: @escaping (String) -> Void) {
        let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        a.addTextField { tf in
            tf.text = current
            tf.keyboardType = .numbersAndPunctuation
            tf.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            if let t = a.textFields?.first?.text { completion(t) }
        })
        present(a, animated: true)
    }

    private func alert(_ msg: String) {
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        present(a, animated: true)
    }

    private func makeHUD(_ text: String) -> UIView {
        let hud = UIView(frame: CGRect(x: (view.bounds.width-120)/2, y: (view.bounds.height-60)/2,
                                       width: 120, height: 60))
        hud.backgroundColor = UIColor(white: 0, alpha: 0.7)
        hud.layer.cornerRadius = 10
        let label = UILabel(frame: hud.bounds)
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14)
        hud.addSubview(label)
        return hud
    }
}

// MARK: - ModelPickerViewController

/// 从 API 拉取到的模型列表，勾选后批量添加
final class ModelPickerViewController: UITableViewController {

    private let available: [String]
    private let alreadyAdded: [String]
    private var selected: Set<String>
    private let completion: ([String]) -> Void

    init(available: [String], alreadyAdded: [String], completion: @escaping ([String]) -> Void) {
        self.available    = available
        self.alreadyAdded = alreadyAdded
        self.selected     = Set(alreadyAdded)
        self.completion   = completion
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择要添加的模型"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done,
                                                            target: self, action: #selector(done))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "M")
        tableView.backgroundColor = .agBackground
    }

    @objc private func done() {
        // Return only newly selected (not already added)
        let newOnes = selected.filter { !alreadyAdded.contains($0) }
        completion(Array(newOnes).sorted())
        navigationController?.popViewController(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        available.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "M")
        let model = available[indexPath.row]
        cell.textLabel?.text = model
        cell.backgroundColor = .white
        let isChecked = selected.contains(model)
        cell.accessoryType = isChecked ? .checkmark : .none
        if alreadyAdded.contains(model) {
            cell.textLabel?.textColor = .gray
            cell.detailTextLabel?.text = "已添加"
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = available[indexPath.row]
        if selected.contains(model) {
            // Don't allow removing already-added models from here
            if !alreadyAdded.contains(model) { selected.remove(model) }
        } else {
            selected.insert(model)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
