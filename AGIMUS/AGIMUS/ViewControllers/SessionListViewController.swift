// 会话列表页：新建 / 重命名 / 删除 / 历史搜索，点击进入聊天
import UIKit

final class SessionListViewController: UITableViewController {

    private var sessions: [ChatSession] = []
    private var filteredSessions: [ChatSession] = []
    private var matchedSnippetsByID: [String: String] = [:]
    private var searchHistory: [String] = []

    private lazy var settingsBtn = UIBarButtonItem(title: "",
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(openSettings))
    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.delegate = self
        controller.delegate = self
        return controller
    }()
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15)
        return label
    }()
    private let searchHistoryKey = "sessionSearchHistory"
    private let maxSearchHistoryCount = 20

    private var normalizedSearchText: String? {
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
    private var isSearchUIActive: Bool { searchController.isActive }
    private var isSearchResultsActive: Bool { isSearchUIActive && normalizedSearchText != nil }
    private var isSearchHistoryMode: Bool { isSearchUIActive && normalizedSearchText == nil }
    private var isSearchActive: Bool { isSearchResultsActive }
    private var displayedSessions: [ChatSession] {
        isSearchActive ? filteredSessions : sessions
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AGIMUS"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newSession))
        navigationItem.rightBarButtonItem = addBtn
        navigationItem.leftBarButtonItem  = settingsBtn

        loadSearchHistory()

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
        applySearch()
    }

    private func applyTheme() {
        tableView.backgroundColor = .agBackground
        tableView.separatorColor  = .agSeparator
        emptyStateLabel.textColor = UIColor.themed(
            light: UIColor(white: 0.45, alpha: 1),
            dark: UIColor(white: 0.55, alpha: 1)
        )
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        updateSearchHistoryHeader()
        updateEmptyState()
        tableView.reloadData()
    }

    private func applyLocalization() {
        settingsBtn.title = L("设置", "Settings")
        searchController.searchBar.placeholder = L("搜索聊天记录", "Search chat history")
        updateSearchHistoryHeader()
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        refresh()
    }

    // MARK: - Data
    private func refresh() {
        sessions = ChatGenerationManager.shared.mergedSessions(SessionStore.shared.sessions)
        applySearch()
    }

    private func applySearch() {
        guard isSearchResultsActive, let query = normalizedSearchText else {
            filteredSessions.removeAll()
            matchedSnippetsByID.removeAll()
            updateSearchHistoryHeader()
            updateEmptyState()
            tableView.reloadData()
            return
        }

        let keywords = normalizedKeywords(from: query)
        var matched: [ChatSession] = []
        var snippets: [String: String] = [:]

        for session in sessions {
            if let snippet = matchedSnippet(in: session, keywords: keywords, rawQuery: query) {
                matched.append(session)
                snippets[session.id] = snippet
            }
        }
        filteredSessions = matched
        matchedSnippetsByID = snippets
        updateSearchHistoryHeader()
        updateEmptyState()
        tableView.reloadData()
    }

    private func updateEmptyState() {
        var shouldShowSeparators = true

        if isSearchHistoryMode {
            emptyStateLabel.text = searchHistory.isEmpty
                ? L("输入关键词开始搜索聊天记录", "Enter keywords to search chat history")
                : nil
            tableView.backgroundView = searchHistory.isEmpty ? emptyStateLabel : nil
            shouldShowSeparators = !searchHistory.isEmpty
            tableView.separatorStyle = shouldShowSeparators ? .singleLine : .none
            return
        }

        if displayedSessions.isEmpty {
            emptyStateLabel.text = isSearchResultsActive
                ? L("没有匹配的聊天记录", "No matching chats")
                : L("还没有会话，点击右上角 + 开始", "No chats yet. Tap + to start")
            tableView.backgroundView = emptyStateLabel
            shouldShowSeparators = false
        } else {
            tableView.backgroundView = nil
        }

        tableView.separatorStyle = shouldShowSeparators ? .singleLine : .none
    }

    private func clearSearch() {
        searchController.searchBar.text = nil
        searchController.isActive = false
        filteredSessions.removeAll()
        matchedSnippetsByID.removeAll()
        tableView.tableHeaderView = nil
    }

    private func normalizedKeywords(from query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map { normalizeForSearch(String($0)) }
    }

    private func normalizeForSearch(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current).lowercased()
    }

    private func compactText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(1, limit - 1))) + "…"
    }

    private func defaultPreview(for session: ChatSession) -> String {
        for message in session.visibleMessages.reversed() {
            let line = compactText(message.content)
            if !line.isEmpty { return truncated(line, limit: 88) }
        }
        return L("暂无消息", "No messages yet")
    }

    private func searchableCandidates(for session: ChatSession) -> [String] {
        var items: [String] = [session.displayTitle, session.title]
        for message in session.visibleMessages.reversed() {
            if !message.content.isEmpty { items.append(message.content) }
            if let thinking = message.thinkingContent, !thinking.isEmpty { items.append(thinking) }
        }
        return items
    }

    private func makeSnippet(from text: String, query: String) -> String {
        let compact = compactText(text)
        guard !compact.isEmpty else { return "" }

        let ns = compact as NSString
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var hit = NSRange(location: NSNotFound, length: 0)
        for term in terms {
            let range = ns.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            if range.location != NSNotFound {
                hit = range
                break
            }
        }
        guard hit.location != NSNotFound else { return truncated(compact, limit: 88) }

        let start = max(0, hit.location - 24)
        let end = min(ns.length, hit.location + hit.length + 56)
        let snippetRange = NSRange(location: start, length: end - start)
        var snippet = ns.substring(with: snippetRange)
        if start > 0 { snippet = "…" + snippet }
        if end < ns.length { snippet += "…" }
        return snippet
    }

    private func matchedSnippet(in session: ChatSession, keywords: [String], rawQuery: String) -> String? {
        guard !keywords.isEmpty else { return nil }

        for candidate in searchableCandidates(for: session) {
            let compact = compactText(candidate)
            guard !compact.isEmpty else { continue }
            let normalized = normalizeForSearch(compact)
            if keywords.allSatisfy({ normalized.contains($0) }) {
                return makeSnippet(from: compact, query: rawQuery)
            }
        }
        return nil
    }

    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: searchHistoryKey) ?? []
    }

    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: searchHistoryKey)
    }

    private func addSearchHistory(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        searchHistory.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        searchHistory.insert(normalized, at: 0)
        if searchHistory.count > maxSearchHistoryCount {
            searchHistory = Array(searchHistory.prefix(maxSearchHistoryCount))
        }
        saveSearchHistory()
    }

    @objc private func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
        applySearch()
    }

    private func updateSearchHistoryHeader() {
        guard isSearchHistoryMode, !searchHistory.isEmpty else {
            tableView.tableHeaderView = nil
            return
        }

        let height: CGFloat = 44
        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height))
        container.backgroundColor = .agBackground

        let button = UIButton(type: .system)
        button.setTitle(L("清除搜索历史", "Clear Search History"), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.setTitleColor(.systemRed, for: .normal)
        button.contentHorizontalAlignment = .right
        button.frame = CGRect(x: 12, y: 6, width: container.bounds.width - 24, height: 32)
        button.autoresizingMask = [.flexibleWidth]
        button.addTarget(self, action: #selector(clearSearchHistory), for: .touchUpInside)
        container.addSubview(button)

        tableView.tableHeaderView = container
    }

    private func highlightedText(_ text: String,
                                 query: String?,
                                 font: UIFont,
                                 color: UIColor) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let result = NSMutableAttributedString(string: text, attributes: attrs)
        let raw = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return result }

        let terms = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return result }

        let source = text as NSString
        let highlightColor = UIColor.themed(
            light: UIColor(red: 1.00, green: 0.92, blue: 0.35, alpha: 0.55),
            dark: UIColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 0.35)
        )

        for term in terms {
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let found = source.range(of: term,
                                         options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchRange)
                if found.location == NSNotFound { break }
                result.addAttribute(.backgroundColor, value: highlightColor, range: found)
                let next = found.location + found.length
                guard next < source.length else { break }
                searchRange = NSRange(location: next, length: source.length - next)
            }
        }

        return result
    }

    // MARK: - TableView DataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearchHistoryMode { return searchHistory.count }
        return displayedSessions.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearchHistoryMode {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SessionCell")
            let term = searchHistory[indexPath.row]
            cell.textLabel?.attributedText = highlightedText(
                term,
                query: normalizedSearchText,
                font: UIFont.systemFont(ofSize: 16, weight: .medium),
                color: .agTextBot
            )
            cell.detailTextLabel?.text = L("历史搜索", "Search history")
            cell.detailTextLabel?.textColor = UIColor.themed(
                light: UIColor(white: 0.50, alpha: 1),
                dark: UIColor(white: 0.54, alpha: 1)
            )
            cell.accessoryType = .none
            cell.backgroundColor = .agCellBackground
            let selView = UIView()
            selView.backgroundColor = .agCellSelection
            cell.selectedBackgroundView = selView
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SessionCell")
        let s = displayedSessions[indexPath.row]
        cell.textLabel?.attributedText = highlightedText(
            s.displayTitle,
            query: isSearchResultsActive ? normalizedSearchText : nil,
            font: UIFont.systemFont(ofSize: 16, weight: .regular),
            color: .agTextBot
        )
        cell.textLabel?.numberOfLines = 1
        let detailColor = UIColor.themed(
            light: UIColor(white: 0.48, alpha: 1),
            dark: UIColor(white: 0.56, alpha: 1)
        )
        let detailText = matchedSnippetsByID[s.id] ?? defaultPreview(for: s)
        cell.detailTextLabel?.attributedText = highlightedText(
            detailText,
            query: isSearchResultsActive ? normalizedSearchText : nil,
            font: UIFont.systemFont(ofSize: 12),
            color: detailColor
        )
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .agCellBackground
        let selView = UIView()
        selView.backgroundColor = .agCellSelection
        cell.selectedBackgroundView = selView
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 62 }

    // MARK: - TableView Delegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearchHistoryMode {
            let keyword = searchHistory[indexPath.row]
            searchController.searchBar.text = keyword
            applySearch()
            return
        }
        if let query = normalizedSearchText { addSearchHistory(query) }
        let vc = ChatViewController(session: displayedSessions[indexPath.row],
                                    highlightQuery: normalizedSearchText)
        navigationController?.pushViewController(vc, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        if isSearchHistoryMode {
            searchHistory.remove(at: indexPath.row)
            saveSearchHistory()
            applySearch()
            return
        }
        let id = displayedSessions[indexPath.row].id
        SessionStore.shared.delete(id: id)
        refresh()
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView,
                            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard !isSearchHistoryMode else { return nil }
        let sessionID = displayedSessions[indexPath.row].id
        let rename = UIContextualAction(style: .normal, title: L("重命名", "Rename")) { [weak self] _, _, done in
            self?.renameSession(sessionID: sessionID)
            done(true)
        }
        rename.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [rename])
    }

    // MARK: - Actions
    @objc private func newSession() {
        clearSearch()
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

    private func renameSession(sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
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
            var updated = session
            updated.title = text.trimmingCharacters(in: .whitespaces)
            updated.updatedAt = Date()
            SessionStore.shared.save(updated)
            self.refresh()
        })
        present(alert, animated: true)
    }
}

extension SessionListViewController: UISearchResultsUpdating, UISearchBarDelegate, UISearchControllerDelegate {
    func updateSearchResults(for searchController: UISearchController) {
        applySearch()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        applySearch()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        if let query = normalizedSearchText { addSearchHistory(query) }
        applySearch()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        applySearch()
    }

    func willPresentSearchController(_ searchController: UISearchController) {
        applySearch()
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        applySearch()
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        applySearch()
    }
}
