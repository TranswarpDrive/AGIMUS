// 会话列表页：新建 / 重命名 / 删除，点击进入聊天
import UIKit

final class SessionListViewController: UITableViewController {

    private var sessions: [ChatSession] = []
    private lazy var settingsBtn = UIBarButtonItem(title: "",
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(openSettings))

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AGIMUS"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SessionCell")

        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newSession))
        navigationItem.rightBarButtonItem = addBtn
        navigationItem.leftBarButtonItem  = settingsBtn

        NotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(languageChanged),
            name: .appLanguageDidChange, object: nil)
        applyLocalization()
        applyTheme()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() { applyTheme() }
    @objc private func languageChanged() {
        applyLocalization()
        tableView.reloadData()
    }

    private func applyTheme() {
        tableView.backgroundColor = .agBackground
        tableView.separatorColor  = .agSeparator
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        tableView.reloadData()
    }

    private func applyLocalization() {
        settingsBtn.title = L("设置", "Settings")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        refresh()
    }

    // MARK: - Data
    private func refresh() {
        sessions = SessionStore.shared.sessions
        tableView.reloadData()
    }

    // MARK: - TableView DataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sessions.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath)
        let s = sessions[indexPath.row]
        cell.textLabel?.text = s.displayTitle
        cell.textLabel?.textColor = .agTextBot
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .agCellBackground
        let selView = UIView()
        selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 56 }

    // MARK: - TableView Delegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = ChatViewController(session: sessions[indexPath.row])
        navigationController?.pushViewController(vc, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let id = sessions[indexPath.row].id
        SessionStore.shared.delete(id: id)
        sessions.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    override func tableView(_ tableView: UITableView,
                            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let rename = UIContextualAction(style: .normal, title: L("重命名", "Rename")) { [weak self] _, _, done in
            self?.renameSession(at: indexPath)
            done(true)
        }
        rename.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [rename])
    }

    // MARK: - Actions
    @objc private func newSession() {
        var session = ChatSession()
        let systemPrompt = SettingsStore.shared.defaultSystemPrompt
        if !systemPrompt.isEmpty {
            session.messages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        SessionStore.shared.save(session)
        refresh()
        let vc = ChatViewController(session: session)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openSettings() {
        let vc = SettingsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func renameSession(at indexPath: IndexPath) {
        let session = sessions[indexPath.row]
        let alert = UIAlertController(title: L("重命名", "Rename"), message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = session.title
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = alert.textFields?.first?.text,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var updated = self.sessions[indexPath.row]
            updated.title = text.trimmingCharacters(in: .whitespaces)
            updated.updatedAt = Date()
            SessionStore.shared.save(updated)
            self.refresh()
        })
        present(alert, animated: true)
    }
}
