// 聊天页：模型选择 / 思考切换 / 搜索工具 / 流式+非流式 / 工具调用 / 自动标题
import UIKit

final class ChatViewController: UIViewController {

    // MARK: - State
    private var session: ChatSession
    private var isGenerating = false
    private var streamingMessageID: String?
    private var streamStartTime: Date?
    private var thinkingExpandedIDs = Set<String>()   // 已展开思考的消息 ID
    private var currentOptions = ChatRequestOptions()
    private var selectedSearchProvider: SearchProvider?

    /// 当前实际使用的 Provider（model 由 session.preferredModel 覆盖）
    private var effectiveProvider: ProviderConfig {
        var p = SettingsStore.shared.activeProvider
        if let m = session.preferredModel, !m.isEmpty { p.activeModel = m }
        return p
    }
    private var effectiveAPIKey: String {
        SettingsStore.shared.apiKey(for: SettingsStore.shared.activeProvider.id)
    }

    // MARK: - Subviews
    private let tableView: UITableView = {
        let tv = UITableView()
        // 聊天室风格：使用细分隔线代替气泡间距
        tv.separatorStyle = .singleLine
        tv.separatorColor = UIColor(white: 0.88, alpha: 1)
        tv.separatorInset = .zero
        tv.backgroundColor = UIColor(white: 0.97, alpha: 1)
        tv.keyboardDismissMode = .interactive
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 80
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let toolbar = ChatToolbarView()
    private let inputBar = InputBarView()
    private var inputBarBottom: NSLayoutConstraint!
    private lazy var tapToDismissKeyboardGR: UITapGestureRecognizer = {
        let gr = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromChatArea))
        gr.cancelsTouchesInView = false
        return gr
    }()

    // MARK: - Init
    init(session: ChatSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNav()
        setupTableView()
        setupToolbarAndInputBar()
        setupKeyboardObservers()
        refreshToolbar()
        applyTheme()
        NotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChange, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(languageChanged),
            name: .appLanguageDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        title = session.displayTitle
        applyTheme()
        refreshToolbar()
        scrollToBottom(animated: false)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() { applyTheme() }
    @objc private func languageChanged() {
        refreshToolbar()
        tableView.reloadData()
    }

    private func applyTheme() {
        view.backgroundColor = .agBackground
        tableView.backgroundColor = .agBackground
        tableView.separatorColor  = .agSeparator
        ThemeManager.shared.styleNavigationBar(navigationController?.navigationBar)
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupNav() {
        title = session.displayTitle
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "•••", style: .plain,
                                                            target: self, action: #selector(showMore))
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseID)
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.addGestureRecognizer(tapToDismissKeyboardGR)
    }

    private func setupToolbarAndInputBar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.delegate = self
        toolbar.setContentHuggingPriority(.required, for: .vertical)
        toolbar.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(toolbar)

        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.delegate = self
        view.addSubview(inputBar)

        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottom
        ])
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    // MARK: - Toolbar state

    private func refreshToolbar() {
        let modelName = session.preferredModel ?? SettingsStore.shared.activeProvider.activeModel
        toolbar.setModel(modelName)

        let isThinkCapable = ChatToolbarView.isThinkingCapable(modelName)
        toolbar.setThinkingVisible(isThinkCapable)
        if !isThinkCapable { currentOptions.thinkingEnabled = false }
        toolbar.setThinkingEnabled(currentOptions.thinkingEnabled)

        let searchProviders = SettingsStore.shared.searchProviders
        toolbar.setSearchVisible(!searchProviders.isEmpty)
        // Validate selected provider still exists
        if let sel = selectedSearchProvider,
           !searchProviders.contains(where: { $0.id == sel.id }) {
            selectedSearchProvider = nil
        }
        toolbar.setSearchLabel(selectedSearchProvider?.displayName ?? AppLanguage.searchDisabledLabel)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let info = note.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }
        let kbHeight = max(view.bounds.height - endFrame.minY, 0)
        inputBarBottom.constant = -kbHeight
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
        scrollToBottom(animated: false)
    }

    @objc private func dismissKeyboardFromChatArea() {
        view.endEditing(true)
    }

    // MARK: - Scroll

    private func scrollToBottom(animated: Bool) {
        let rows = session.visibleMessages.count
        guard rows > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: rows - 1, section: 0), at: .bottom, animated: animated)
    }

    // MARK: - Send (entry point)

    private func send(text: String) {
        inputBar.clear()
        inputBar.setGenerating(true)
        isGenerating = true

        let userMsg = ChatMessage(role: .user, content: text)
        session.messages.append(userMsg)
        session.updatedAt = Date()
        insertLastRow()

        streamStartTime = Date()
        currentOptions.searchTool = selectedSearchProvider
        let requestMessages = session.messages

        let provider = effectiveProvider
        let key      = effectiveAPIKey

        if provider.useStream {
            // 先拍平当前消息快照用于请求，再插入本地占位消息，避免：
            // 1) 空 assistant 占位被发给服务端
            // 2) 首个流式分片在占位消息插入前到达，导致内容被丢弃
            var placeholder = ChatMessage(role: .assistant, content: "")
            streamingMessageID = placeholder.id
            session.messages.append(placeholder)
            insertLastRow()
            ChatAPIService.shared.streamDelegate = self
            ChatAPIService.shared.sendStream(messages: requestMessages,
                                             config: provider, apiKey: key,
                                             options: currentOptions)
        } else {
            // 非流式同样使用请求快照，保证发给服务端的消息不含本地占位消息
            var placeholder = ChatMessage(role: .assistant, content: "")
            streamingMessageID = placeholder.id
            session.messages.append(placeholder)
            insertLastRow()
            sendNonStreaming(messages: requestMessages, provider: provider, key: key, failMsgID: userMsg.id)
        }
    }

    private func sendNonStreaming(messages: [ChatMessage], provider: ProviderConfig, key: String, failMsgID: String) {
        let startTime = streamStartTime ?? Date()
        ChatAPIService.shared.send(messages: messages,
                                   config: provider, apiKey: key,
                                   options: currentOptions) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let apiResult):
                switch apiResult.kind {
                case .message(let content, let thinking):
                    let elapsed = Date().timeIntervalSince(startTime)
                    // 找到占位消息，就地更新内容（替换打字动画）；找不到则兜底追加
                    if let sid = self.streamingMessageID,
                       let idx = self.session.messages.firstIndex(where: { $0.id == sid }) {
                        self.session.messages[idx].content        = content
                        self.session.messages[idx].thinkingContent = thinking
                        self.session.messages[idx].modelName      = apiResult.model
                        self.session.messages[idx].elapsedSeconds = elapsed
                        self.session.messages[idx].tokenUsage     = apiResult.usage
                        self.session.updatedAt = Date()
                        self.reloadLastRow()
                    } else {
                        var reply = ChatMessage(role: .assistant, content: content)
                        reply.thinkingContent = thinking
                        reply.modelName       = apiResult.model
                        reply.elapsedSeconds  = elapsed
                        reply.tokenUsage      = apiResult.usage
                        self.session.messages.append(reply)
                        self.session.updatedAt = Date()
                        self.insertLastRow()
                    }
                    self.finishGeneration()
                    self.tryGenerateTitle()

                case .toolCalls(let calls):
                    // tool call：先移除占位，再走工具调用流程
                    if let sid = self.streamingMessageID,
                       let idx = self.session.messages.firstIndex(where: { $0.id == sid }) {
                        self.session.messages.remove(at: idx)
                    }
                    self.handleToolCalls(calls, model: apiResult.model, startTime: startTime)
                }

            case .failure(let err):
                self.isGenerating = false
                self.inputBar.setGenerating(false)
                // 移除打字占位
                if let sid = self.streamingMessageID,
                   let idx = self.session.messages.firstIndex(where: { $0.id == sid }) {
                    self.session.messages.remove(at: idx)
                    self.tableView.reloadData()
                }
                if let idx = self.session.messages.lastIndex(where: { $0.id == failMsgID }) {
                    self.session.messages[idx].isError = true
                    self.tableView.reloadData()
                }
                self.showError(err.localizedDescription)
            }
        }
    }

    // MARK: - Tool call execution

    private func handleToolCalls(_ calls: [[String: Any]], model: String?, startTime: Date) {
        // Insert invisible assistant message carrying tool_calls JSON
        var toolCallMsg = ChatMessage(role: .assistant, content: "")
        toolCallMsg.modelName = model
        if let data = try? JSONSerialization.data(withJSONObject: calls),
           let str  = String(data: data, encoding: .utf8) {
            toolCallMsg.toolCallsJSON = str
        }
        session.messages.append(toolCallMsg)

        guard let sp = selectedSearchProvider else {
            // No search provider configured; just finish
            finishGeneration()
            return
        }

        let group = DispatchGroup()
        var results: [(callId: String, result: String)] = []
        let lock = NSLock()

        for call in calls {
            guard let callId   = call["id"] as? String,
                  let fn       = call["function"] as? [String: Any],
                  let name     = fn["name"] as? String, name == "web_search",
                  let argsStr  = fn["arguments"] as? String,
                  let argsData = argsStr.data(using: .utf8),
                  let args     = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
                  let query    = args["query"] as? String
            else { continue }

            let apiKey = SettingsStore.shared.searchAPIKey(for: sp.id)
            group.enter()
            SearchService.shared.search(query: query, provider: sp, apiKey: apiKey) { res in
                let text: String
                switch res {
                case .success(let formatted): text = formatted
                case .failure(let err):       text = L("搜索失败: \(err.localizedDescription)",
                                                     "Search failed: \(err.localizedDescription)")
                }
                lock.lock(); results.append((callId: callId, result: text)); lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            for r in results {
                var toolMsg = ChatMessage(role: .tool, content: r.result)
                toolMsg.toolCallId = r.callId
                self.session.messages.append(toolMsg)
            }
            // Continue non-streaming (no nested tool calls)
            let provider = self.effectiveProvider
            let key      = self.effectiveAPIKey
            var opts     = self.currentOptions
            opts.searchTool = nil     // don't re-trigger search in continuation

            ChatAPIService.shared.send(messages: self.session.messages,
                                       config: provider, apiKey: key,
                                       options: opts) { [weak self] res in
                guard let self = self else { return }
                switch res {
                case .success(let apiResult):
                    if case .message(let content, let thinking) = apiResult.kind {
                        let elapsed = Date().timeIntervalSince(startTime)
                        var reply = ChatMessage(role: .assistant, content: content)
                        reply.thinkingContent = thinking
                        reply.modelName       = apiResult.model
                        reply.elapsedSeconds  = elapsed
                        reply.tokenUsage      = apiResult.usage
                        self.session.messages.append(reply)
                        self.session.updatedAt = Date()
                        self.tableView.reloadData()
                        self.scrollToBottom(animated: true)
                    }
                case .failure(let err):
                    self.showError(err.localizedDescription)
                }
                self.finishGeneration()
                self.tryGenerateTitle()
            }
        }
    }

    private func finishGeneration() {
        isGenerating = false
        inputBar.setGenerating(false)
        session.updatedAt = Date()
        SessionStore.shared.save(session)
        streamingMessageID = nil
        streamStartTime    = nil
        // Re-render last cell so cursor "▌" is removed now that isGenerating is false
        reloadLastRow()
    }

    // MARK: - Auto title

    private func tryGenerateTitle() {
        guard AppLanguage.isDefaultSessionTitle(session.title) else { return }
        let userMsgs = session.messages.filter { $0.role == .user  && !$0.isError }
        let botMsgs  = session.messages.filter { $0.role == .assistant && $0.toolCallsJSON == nil }
        guard userMsgs.count == 1, let firstUser = userMsgs.first,
              botMsgs.count  >= 1, let firstBot  = botMsgs.first else { return }

        let titleProvider = SettingsStore.shared.effectiveTitleProvider
        let titleKey      = SettingsStore.shared.apiKey(for: titleProvider.id)
        var cfg           = titleProvider
        cfg.activeModel   = SettingsStore.shared.effectiveTitleModel
        cfg.maxTokens     = 60
        cfg.useStream     = false

        let sys  = ChatMessage(role: .system, content: AppLanguage.titleGenerationPrompt)
        let msgs = [sys, firstUser, firstBot]

        ChatAPIService.shared.sendOneshot(messages: msgs, config: cfg, apiKey: titleKey) { [weak self] result in
            // 若模型不可用或返回失败，静默忽略，保留默认标题"新对话"
            guard let self = self, case .success(let raw) = result else { return }
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "《",  with: "")
                .replacingOccurrences(of: "》",  with: "")
                .replacingOccurrences(of: "「",  with: "")
                .replacingOccurrences(of: "」",  with: "")
            guard !cleaned.isEmpty else { return }
            self.session.title = cleaned
            self.title = cleaned
            SessionStore.shared.save(self.session)
        }
    }

    // MARK: - TableView helpers

    private func insertLastRow() {
        let idx = IndexPath(row: session.visibleMessages.count - 1, section: 0)
        tableView.insertRows(at: [idx], with: .none)
        scrollToBottom(animated: true)
    }

    private func reloadLastRow() {
        let count = session.visibleMessages.count
        guard count > 0 else { return }
        tableView.reloadRows(at: [IndexPath(row: count - 1, section: 0)], with: .none)
    }

    private func reloadRow(_ row: Int) {
        guard row >= 0, row < session.visibleMessages.count else { return }
        tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
    }

    // MARK: - Nav actions

    @objc private func showMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("重命名会话", "Rename Chat"), style: .default) { [weak self] _ in
            self?.renameSession()
        })
        sheet.addAction(UIAlertAction(title: L("重新生成标题", "Regenerate Title"), style: .default) { [weak self] _ in
            self?.regenerateTitle()
        })
        sheet.addAction(UIAlertAction(title: L("编辑最后一条消息", "Edit Last Message"), style: .default) { [weak self] _ in
            self?.editLastMessage()
        })
        sheet.addAction(UIAlertAction(title: L("清空消息", "Clear Messages"), style: .destructive) { [weak self] _ in
            self?.clearMessages()
        })
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    /// 无论当前标题是什么，强制重新调用 AI 生成标题
    private func regenerateTitle() {
        let userMsgs = session.messages.filter { $0.role == .user && !$0.isError }
        let botMsgs  = session.messages.filter {
            $0.role == .assistant && $0.toolCallsJSON == nil && !$0.content.isEmpty
        }
        guard let firstUser = userMsgs.first, let firstBot = botMsgs.first else {
            let a = UIAlertController(title: L("无法生成标题", "Unable to Generate Title"),
                                      message: L("需要至少一轮完整对话", "At least one complete round of conversation is required."),
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
            present(a, animated: true)
            return
        }
        let titleProvider = SettingsStore.shared.effectiveTitleProvider
        let titleKey      = SettingsStore.shared.apiKey(for: titleProvider.id)
        var cfg           = titleProvider
        cfg.activeModel   = SettingsStore.shared.effectiveTitleModel
        cfg.maxTokens     = 60
        cfg.useStream     = false
        let sys  = ChatMessage(role: .system, content: AppLanguage.titleGenerationPrompt)
        ChatAPIService.shared.sendOneshot(messages: [sys, firstUser, firstBot],
                                          config: cfg, apiKey: titleKey) { [weak self] result in
            guard let self = self, case .success(let raw) = result else { return }
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "《", with: "")
                .replacingOccurrences(of: "》", with: "")
            guard !cleaned.isEmpty else { return }
            self.session.title = cleaned
            self.title = cleaned
            SessionStore.shared.save(self.session)
        }
    }

    private func renameSession() {
        let a = UIAlertController(title: L("重命名", "Rename"), message: nil, preferredStyle: .alert)
        a.addTextField { [weak self] tf in tf.text = self?.session.title }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("确定", "OK"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }
            self.session.title = text
            self.session.updatedAt = Date()
            self.title = text
            SessionStore.shared.save(self.session)
        })
        present(a, animated: true)
    }

    private func editLastMessage() {
        guard let last = session.messages.last(where: { $0.role == .user && !$0.isError }) else { return }
        let a = UIAlertController(title: L("编辑消息", "Edit Message"), message: nil, preferredStyle: .alert)
        a.addTextField { tf in tf.text = last.content }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("重发", "Resend"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }
            if let idx = self.session.messages.lastIndex(where: { $0.id == last.id }) {
                self.session.messages.removeSubrange(idx...)
            }
            self.tableView.reloadData()
            self.send(text: text)
        })
        present(a, animated: true)
    }

    private func clearMessages() {
        session.messages = session.messages.filter { $0.role == .system }
        session.updatedAt = Date()
        SessionStore.shared.save(session)
        tableView.reloadData()
    }

    private func showError(_ message: String) {
        let a = UIAlertController(title: L("请求失败", "Request Failed"), message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
        present(a, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        session.visibleMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseID,
                                                 for: indexPath) as! MessageCell
        let msg    = session.visibleMessages[indexPath.row]
        let isLast = indexPath.row == session.visibleMessages.count - 1
        let isExpanded = thinkingExpandedIDs.contains(msg.id)
        cell.configure(with: msg,
                       isGenerating: isGenerating && isLast && msg.role == .assistant,
                       isThinkingExpanded: isExpanded)
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ChatViewController: UITableViewDelegate {}

// MARK: - InputBarViewDelegate
extension ChatViewController: InputBarViewDelegate {
    func inputBarDidTapSend(_ bar: InputBarView, text: String) {
        guard !isGenerating else { return }
        send(text: text)
    }

    func inputBarDidTapStop(_ bar: InputBarView) {
        ChatAPIService.shared.cancel()
        isGenerating = false
        inputBar.setGenerating(false)

        if let id = streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == id }) {
            if session.messages[idx].content.isEmpty && session.messages[idx].thinkingContent == nil {
                session.messages.remove(at: idx)
                tableView.reloadData()
            } else {
                let elapsed = streamStartTime.map { Date().timeIntervalSince($0) }
                session.messages[idx].elapsedSeconds = elapsed
                session.updatedAt = Date()
                SessionStore.shared.save(session)
                reloadLastRow()
            }
        }
        streamingMessageID = nil
        streamStartTime    = nil
    }
}

// MARK: - MessageCellDelegate
extension ChatViewController: MessageCellDelegate {
    func messageCellDidTapRetry(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        let msg = session.visibleMessages[ip.row]
        guard msg.isError else { return }
        if let idx = session.messages.firstIndex(where: { $0.id == msg.id }) {
            session.messages.remove(at: idx)
            tableView.deleteRows(at: [ip], with: .automatic)
        }
        send(text: msg.content)
    }

    func messageCellDidTapCopy(_ cell: MessageCell, text: String) {
        UIPasteboard.general.string = text
        let hud = UILabel()
        hud.text = L("已复制", "Copied")
        hud.font = UIFont.systemFont(ofSize: 14)
        hud.textColor = .white
        hud.backgroundColor = UIColor(white: 0, alpha: 0.72)
        hud.textAlignment = .center
        hud.layer.cornerRadius = 8
        hud.clipsToBounds = true
        hud.frame = CGRect(x: (view.bounds.width - 80) / 2,
                           y: view.bounds.height / 2 - 18,
                           width: 80, height: 36)
        view.addSubview(hud)
        UIView.animate(withDuration: 0.3, delay: 1.0, options: [],
                       animations: { hud.alpha = 0 }) { _ in hud.removeFromSuperview() }
    }

    func messageCellDidToggleThinking(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        let msg = session.visibleMessages[ip.row]
        if thinkingExpandedIDs.contains(msg.id) {
            thinkingExpandedIDs.remove(msg.id)
        } else {
            thinkingExpandedIDs.insert(msg.id)
        }
        tableView.beginUpdates()
        tableView.endUpdates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.scrollToBottom(animated: true)
        }
    }
}

// MARK: - ChatToolbarViewDelegate
extension ChatViewController: ChatToolbarViewDelegate {
    func toolbarDidTapModelSelector(_ toolbar: ChatToolbarView) {
        let provider = SettingsStore.shared.activeProvider
        let current  = session.preferredModel ?? provider.activeModel
        guard !provider.models.isEmpty else {
            let a = UIAlertController(title: L("无可用模型", "No Models Available"),
                                      message: L("请先在设置 → 提供商中添加模型",
                                                 "Please add a model in Settings -> Providers first."),
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
            present(a, animated: true)
            return
        }
        let sheet = UIAlertController(title: L("选择模型", "Choose Model"), message: nil, preferredStyle: .actionSheet)
        for m in provider.models {
            let isCurrent = (m == current)
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(m)" : m, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.session.preferredModel = m
                SessionStore.shared.save(self.session)
                self.refreshToolbar()
            })
        }
        sheet.addAction(UIAlertAction(title: L("跟随提供商默认", "Follow Provider Default"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.session.preferredModel = nil
            SessionStore.shared.save(self.session)
            self.refreshToolbar()
        })
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    func toolbarDidTapThinking(_ toolbar: ChatToolbarView) {
        currentOptions.thinkingEnabled = !currentOptions.thinkingEnabled
        toolbar.setThinkingEnabled(currentOptions.thinkingEnabled)
    }

    func toolbarDidTapSearch(_ toolbar: ChatToolbarView) {
        let providers = SettingsStore.shared.searchProviders
        let sheet = UIAlertController(title: L("搜索服务", "Search Service"), message: nil, preferredStyle: .actionSheet)

        let noSearch = selectedSearchProvider == nil
        sheet.addAction(UIAlertAction(title: noSearch ? "✓ \(AppLanguage.searchDisabledLabel)" : AppLanguage.searchDisabledLabel,
                                      style: .default) { [weak self] _ in
            self?.selectedSearchProvider = nil
            self?.refreshToolbar()
        })
        for sp in providers {
            let isCurrent = selectedSearchProvider?.id == sp.id
            let displayName = sp.displayName
            sheet.addAction(UIAlertAction(title: isCurrent ? "✓ \(displayName)" : displayName,
                                          style: .default) { [weak self] _ in
                self?.selectedSearchProvider = sp
                self?.refreshToolbar()
            })
        }
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }
}

// MARK: - ChatAPIServiceDelegate (streaming)
extension ChatViewController: ChatAPIServiceDelegate {

    func apiServiceDidReceiveContentChunk(_ chunk: String) {
        guard let id  = streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == id }) else { return }
        session.messages[idx].content += chunk
        reloadLastRow()
        scrollToBottom(animated: false)
    }

    func apiServiceDidReceiveThinkingChunk(_ chunk: String) {
        guard let id  = streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == id }) else { return }
        if session.messages[idx].thinkingContent == nil {
            session.messages[idx].thinkingContent = chunk
        } else {
            session.messages[idx].thinkingContent! += chunk
        }
        reloadLastRow()
        scrollToBottom(animated: false)
    }

    func apiServiceDidFinishStream(model: String?, usage: TokenUsage?) {
        if let id  = streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == id }) {
            let elapsed = streamStartTime.map { Date().timeIntervalSince($0) }
            session.messages[idx].modelName      = model
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage     = usage
#if DEBUG
            if session.messages[idx].content.isEmpty,
               (session.messages[idx].thinkingContent ?? "").isEmpty {
                showError(L("流式返回为空。\n\n调试信息：\n\(ChatAPIService.shared.debugLastStreamSummary)",
                            "Stream returned empty.\n\nDebug info:\n\(ChatAPIService.shared.debugLastStreamSummary)"))
            }
#endif
        }
        finishGeneration()   // includes reloadLastRow()
        tryGenerateTitle()
    }

    func apiServiceDidReceiveToolCalls(_ calls: [[String: Any]], model: String?, usage: TokenUsage?) {
        // Update streaming placeholder with tool_calls info
        if let id  = streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == id }) {
            session.messages[idx].modelName  = model
            session.messages[idx].tokenUsage = usage
            if let data = try? JSONSerialization.data(withJSONObject: calls),
               let str  = String(data: data, encoding: .utf8) {
                session.messages[idx].toolCallsJSON = str
            }
        }
        let startTime = streamStartTime ?? Date()
        streamingMessageID = nil
        streamStartTime    = nil

        tableView.reloadData()
        scrollToBottom(animated: true)

        handleToolCalls(calls, model: model, startTime: startTime)
    }

    func apiServiceDidFail(_ error: Error) {
        isGenerating = false
        inputBar.setGenerating(false)
        if let id  = streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == id }),
           session.messages[idx].content.isEmpty,
           session.messages[idx].thinkingContent == nil {
            session.messages.remove(at: idx)
            tableView.reloadData()
        }
        streamingMessageID = nil
        streamStartTime    = nil
        showError(error.localizedDescription)
    }
}
