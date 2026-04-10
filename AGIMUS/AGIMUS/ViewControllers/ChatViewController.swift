// 聊天页：模型选择 / 思考切换 / 搜索工具 / 流式+非流式 / 工具调用 / 自动标题
import UIKit

final class ChatViewController: UIViewController {

    private struct ActiveVersionMutation {
        let assistantMessageID: String
        let userMessageID: String
    }

    private enum StreamDisplaySegmentKind {
        case thinking
        case content
    }

    private struct StreamDisplaySegment {
        let kind: StreamDisplaySegmentKind
        var units: [String]
    }

    private struct PendingStreamCompletion {
        let model: String?
        let usage: TokenUsage?
    }

    private struct PendingToolCallDispatch {
        let calls: [[String: Any]]
        let model: String?
        let usage: TokenUsage?
        let startTime: Date
    }

    // MARK: - State
    private var session: ChatSession
    private var isGenerating = false
    private var streamingMessageID: String?
    private var streamStartTime: Date?
    private var thinkingExpandedIDs = Set<String>()   // 已展开思考的消息 ID
    private var currentPageByMessageID: [String: Int] = [:]
    private var activeVersionMutation: ActiveVersionMutation?
    private var pendingStreamSegments: [StreamDisplaySegment] = []
    private var streamDisplayTimer: Timer?
    private var pendingStreamCompletion: PendingStreamCompletion?
    private var pendingToolCallDispatch: PendingToolCallDispatch?
    private var isThinkingStreaming = false
    private var currentOptions = ChatRequestOptions()
    private var selectedSearchProvider: SearchProvider?
    private let highlightQuery: String?
    private var latestRegeneratableAssistantMessageID: String? {
        guard let last = session.visibleMessages.last,
              last.role == .assistant,
              last.toolCallsJSON == nil
        else { return nil }

        let hasDisplayableContent = !last.content.isEmpty || !((last.thinkingContent ?? "").isEmpty)
        return hasDisplayableContent ? last.id : nil
    }
    private var latestEditableUserMessageID: String? {
        guard !session.messages.isEmpty else { return nil }

        for index in stride(from: session.messages.count - 1, through: 0, by: -1) {
            let message = session.messages[index]
            guard message.role == .user else { continue }
            guard index + 1 < session.messages.count else { continue }

            let hasLaterReply = session.messages[(index + 1)..<session.messages.count].contains { later in
                later.role == .assistant &&
                later.toolCallsJSON == nil &&
                (!later.content.isEmpty || !((later.thinkingContent ?? "").isEmpty))
            }
            if hasLaterReply { return message.id }
        }
        return nil
    }

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
    init(session: ChatSession, highlightQuery: String? = nil) {
        self.session = session
        let q = highlightQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.highlightQuery = q.isEmpty ? nil : q
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
        NotificationCenter.default.addObserver(self,
            selector: #selector(generationManagerChanged(_:)),
            name: .chatGenerationManagerDidUpdate, object: nil)
        syncSessionStateFromManager(reloadTable: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncSessionStateFromManager()
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

    @objc private func generationManagerChanged(_ note: Notification) {
        guard let sessionID = note.userInfo?["sessionID"] as? String,
              sessionID == session.id
        else { return }
        let shouldFollowBottom = isNearBottom()
        let previousVisibleCount = session.visibleMessages.count
        let previousStreamingMessageID = streamingMessageID
        syncSessionStateFromManager(reloadTable: false)

        if session.visibleMessages.count != previousVisibleCount {
            tableView.reloadData()
        } else if let streamingMessageID,
                  streamingMessageID == previousStreamingMessageID,
                  let row = session.visibleMessages.firstIndex(where: { $0.id == streamingMessageID }) {
            reloadRow(row)
        } else {
            tableView.reloadData()
        }

        if shouldFollowBottom && isGenerating {
            scrollToBottom(animated: false)
        }
    }

    private func syncSessionStateFromManager(reloadTable: Bool = true) {
        guard let state = ChatGenerationManager.shared.state(for: session.id) else { return }
        session = state.session
        isGenerating = state.isGenerating
        streamingMessageID = state.streamingMessageID
        isThinkingStreaming = state.isThinkingStreaming
        if state.isGenerating {
            currentOptions = state.requestOptions ?? ChatRequestOptions()
            selectedSearchProvider = state.selectedSearchProvider
        }
        inputBar.setGenerating(isGenerating)
        title = session.displayTitle
        refreshToolbar()
        if reloadTable {
            tableView.reloadData()
        }
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
        let shouldFollowBottom = isNearBottom()
        guard let info = note.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }
        let kbHeight = max(view.bounds.height - endFrame.minY, 0)
        inputBarBottom.constant = -kbHeight
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
        if shouldFollowBottom {
            scrollToBottom(animated: false)
        }
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

    private func isNearBottom(threshold: CGFloat = 80) -> Bool {
        let contentHeight = tableView.contentSize.height
        let visibleHeight = tableView.bounds.height - tableView.adjustedContentInset.top - tableView.adjustedContentInset.bottom
        guard contentHeight > 0, visibleHeight > 0 else { return true }
        let visibleMaxY = tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        return contentHeight - visibleMaxY <= threshold
    }

    private func currentPage(for message: ChatMessage) -> Int {
        let stored = currentPageByMessageID[message.id] ?? message.latestPageIndex
        let clamped = min(max(0, stored), message.latestPageIndex)
        if stored != clamped {
            currentPageByMessageID[message.id] = clamped
        }
        return clamped
    }

    private func resetToLatestPage(for messageID: String) {
        guard let message = session.messages.first(where: { $0.id == messageID }) else { return }
        currentPageByMessageID[messageID] = message.latestPageIndex
    }

    private func stepPage(for messageID: String, delta: Int) {
        guard let row = session.visibleMessages.firstIndex(where: { $0.id == messageID }),
              let messageIndex = session.messages.firstIndex(where: { $0.id == messageID }) else { return }

        let message = session.messages[messageIndex]
        let current = currentPage(for: message)
        let next = min(max(0, current + delta), message.latestPageIndex)
        guard next != current else { return }

        currentPageByMessageID[messageID] = next
        let indexPath = IndexPath(row: row, section: 0)

        if let cell = tableView.cellForRow(at: indexPath) {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = delta < 0 ? .fromLeft : .fromRight
            transition.duration = 0.24
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cell.contentView.layer.add(transition, forKey: "message-version-transition")
        }

        UIView.performWithoutAnimation {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    private func resetStreamRenderingState() {
        streamDisplayTimer?.invalidate()
        streamDisplayTimer = nil
        pendingStreamSegments.removeAll()
        pendingStreamCompletion = nil
        pendingToolCallDispatch = nil
        isThinkingStreaming = false
    }

    private func reloadStreamingMessageRow() {
        guard let messageID = streamingMessageID,
              let row = session.visibleMessages.firstIndex(where: { $0.id == messageID }) else {
            tableView.reloadData()
            return
        }
        reloadRow(row)
    }

    private func ensureThinkingPlaceholderVisible() {
        let shouldFollowBottom = isNearBottom()
        guard let messageID = streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
        if session.messages[idx].thinkingContent == nil {
            session.messages[idx].thinkingContent = ""
            reloadStreamingMessageRow()
            if shouldFollowBottom {
                scrollToBottom(animated: false)
            }
        }
    }

    private func enqueueStreamText(_ text: String, kind: StreamDisplaySegmentKind) {
        guard streamingMessageID != nil else { return }

        if kind == .thinking {
            isThinkingStreaming = true
            ensureThinkingPlaceholderVisible()
        }
        guard !text.isEmpty else { return }

        pendingStreamSegments.append(StreamDisplaySegment(kind: kind, units: text.map { String($0) }))
        startStreamDisplayTimerIfNeeded()
    }

    private func startStreamDisplayTimerIfNeeded() {
        guard streamDisplayTimer == nil else { return }
        let timer = Timer(timeInterval: 0.018, repeats: true) { [weak self] _ in
            self?.appendNextQueuedStreamUnit()
        }
        streamDisplayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func appendNextQueuedStreamUnit() {
        let shouldFollowBottom = isNearBottom()
        guard let messageID = streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == messageID }) else {
            resetStreamRenderingState()
            return
        }

        guard !pendingStreamSegments.isEmpty else {
            completePendingStreamWorkIfPossible()
            return
        }

        var segment = pendingStreamSegments.removeFirst()
        let unit = segment.units.removeFirst()

        switch segment.kind {
        case .thinking:
            isThinkingStreaming = true
            if session.messages[idx].thinkingContent == nil {
                session.messages[idx].thinkingContent = ""
            }
            session.messages[idx].thinkingContent! += unit
        case .content:
            isThinkingStreaming = false
            session.messages[idx].content += unit
        }

        if !segment.units.isEmpty {
            pendingStreamSegments.insert(segment, at: 0)
        }

        reloadStreamingMessageRow()
        if shouldFollowBottom {
            scrollToBottom(animated: false)
        }

        if pendingStreamSegments.isEmpty {
            completePendingStreamWorkIfPossible()
        }
    }

    private func completePendingStreamWorkIfPossible() {
        guard pendingStreamSegments.isEmpty else { return }

        streamDisplayTimer?.invalidate()
        streamDisplayTimer = nil
        let shouldFollowBottom = isNearBottom()

        if let pendingToolCallDispatch {
            self.pendingToolCallDispatch = nil
            tableView.reloadData()
            if shouldFollowBottom {
                scrollToBottom(animated: true)
            }
            handleToolCalls(pendingToolCallDispatch.calls,
                            model: pendingToolCallDispatch.model,
                            startTime: pendingToolCallDispatch.startTime,
                            targetAssistantMessageID: streamingMessageID)
            return
        }

        if let pendingStreamCompletion {
            self.pendingStreamCompletion = nil
            finalizeStreamDisplay(model: pendingStreamCompletion.model,
                                  usage: pendingStreamCompletion.usage)
        }
    }

    private func finalizeStreamDisplay(model: String?, usage: TokenUsage?) {
        if let id = streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == id }) {
            let elapsed = streamStartTime.map { Date().timeIntervalSince($0) }
            session.messages[idx].modelName = model
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage = usage
            isThinkingStreaming = false

            if session.messages[idx].content.isEmpty,
               (session.messages[idx].thinkingContent ?? "").isEmpty {
                let details: String
#if DEBUG
                details = L("流式返回为空。\n\n调试信息：\n\(ChatAPIService.shared.debugLastStreamSummary)",
                            "Stream returned empty.\n\nDebug info:\n\(ChatAPIService.shared.debugLastStreamSummary)")
#else
                details = L("流式返回为空，请检查 API 配置、模型设置或服务端状态。",
                            "The stream returned an empty reply. Please check the API config, model settings, or server status.")
#endif
                presentGenerationErrorAsAssistant(details, model: model)
                return
            }
        }

        finishGeneration()
        tryGenerateTitle()
    }

    private func hasDisplayableContent(for messageID: String?) -> Bool {
        guard let messageID,
              let idx = session.messages.firstIndex(where: { $0.id == messageID }) else { return false }
        let message = session.messages[idx]
        return !message.content.isEmpty || !((message.thinkingContent ?? "").isEmpty)
    }

    private func rollbackActiveVersionMutation() {
        guard let mutation = activeVersionMutation else { return }

        if let assistantIndex = session.messages.firstIndex(where: { $0.id == mutation.assistantMessageID }) {
            session.messages[assistantIndex].restorePreviousVersion()
            resetToLatestPage(for: mutation.assistantMessageID)
        }
        if let userIndex = session.messages.firstIndex(where: { $0.id == mutation.userMessageID }) {
            session.messages[userIndex].restorePreviousVersion()
            resetToLatestPage(for: mutation.userMessageID)
        }

        session.updatedAt = Date()
        SessionStore.shared.save(session)
        tableView.reloadData()
    }

    private func formatAssistantErrorMessage(_ details: String) -> String {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty
            ? L("发生了未知错误。", "An unknown error occurred.")
            : trimmed
        return L("请求失败\n\n\(body)", "Request failed\n\n\(body)")
    }

    private func presentGenerationErrorAsAssistant(_ details: String, model: String? = nil) {
        let messageText = formatAssistantErrorMessage(details)
        let targetID = streamingMessageID
        let elapsed = streamStartTime.map { Date().timeIntervalSince($0) }
        let shouldFollowBottom = isNearBottom()
        resetStreamRenderingState()
        isGenerating = false
        inputBar.setGenerating(false)
        activeVersionMutation = nil
        streamingMessageID = nil
        streamStartTime = nil

        if let targetID,
           let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
            session.messages[idx].content = messageText
            session.messages[idx].thinkingContent = nil
            session.messages[idx].isError = true
            session.messages[idx].toolCallsJSON = nil
            session.messages[idx].modelName = model ?? session.messages[idx].modelName ?? effectiveProvider.activeModel
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage = nil
            resetToLatestPage(for: targetID)
            session.updatedAt = Date()
            SessionStore.shared.save(session)
            if let row = session.visibleMessages.firstIndex(where: { $0.id == targetID }) {
                reloadRow(row)
            } else {
                tableView.reloadData()
            }
        } else {
            var reply = ChatMessage(role: .assistant, content: messageText, isError: true)
            reply.modelName = model ?? effectiveProvider.activeModel
            reply.elapsedSeconds = elapsed
            session.messages.append(reply)
            session.updatedAt = Date()
            SessionStore.shared.save(session)
            tableView.reloadData()
        }

        if shouldFollowBottom {
            scrollToBottom(animated: true)
        }
    }

    private func interruptCurrentGeneration() {
        resetStreamRenderingState()
        if let targetID = streamingMessageID {
            if hasDisplayableContent(for: targetID) {
                if let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
                    session.messages[idx].elapsedSeconds = streamStartTime.map { Date().timeIntervalSince($0) }
                    session.updatedAt = Date()
                    SessionStore.shared.save(session)
                    if let row = session.visibleMessages.firstIndex(where: { $0.id == targetID }) {
                        reloadRow(row)
                    } else {
                        tableView.reloadData()
                    }
                }
            } else if activeVersionMutation != nil {
                rollbackActiveVersionMutation()
            } else if let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
                session.messages.remove(at: idx)
                session.updatedAt = Date()
                SessionStore.shared.save(session)
                tableView.reloadData()
            }
        }

        isGenerating = false
        inputBar.setGenerating(false)
        activeVersionMutation = nil
        streamingMessageID = nil
        streamStartTime = nil
    }

    // MARK: - Send (entry point)

    private func presentBackgroundGenerationBusyAlert() {
        let alert = UIAlertController(title: L("后台回复进行中", "Reply Still Running"),
                                      message: L("另一条会话里的 AI 回复仍在后台生成。请先回到那个会话停止或等它完成，再开始新的生成。",
                                                 "An AI reply in another chat is still generating in the background. Please stop it or wait for it to finish before starting a new one."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
        present(alert, animated: true)
    }

    private func send(text: String) {
        guard ChatGenerationManager.shared.canStartOperation(for: session.id) else {
            presentBackgroundGenerationBusyAlert()
            return
        }
        inputBar.clear()
        guard ChatGenerationManager.shared.send(text: text,
                                                in: session,
                                                options: currentOptions,
                                                searchProvider: selectedSearchProvider) else {
            return
        }
        syncSessionStateFromManager()
        scrollToBottom(animated: true)
    }

    private func startGeneratingReply(with requestMessages: [ChatMessage],
                                      targetAssistantMessageID: String?,
                                      userMessageIDForNewPage: String?) {
        let provider = effectiveProvider
        let key      = effectiveAPIKey
        resetStreamRenderingState()

        if let targetAssistantMessageID = targetAssistantMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == targetAssistantMessageID }) {
            if let userMessageIDForNewPage {
                activeVersionMutation = ActiveVersionMutation(assistantMessageID: targetAssistantMessageID,
                                                              userMessageID: userMessageIDForNewPage)
            } else {
                activeVersionMutation = nil
            }
            session.messages[idx].prepareForNewVersion()
            session.updatedAt = Date()
            SessionStore.shared.save(session)
            streamingMessageID = targetAssistantMessageID
            resetToLatestPage(for: targetAssistantMessageID)
            if let row = session.visibleMessages.firstIndex(where: { $0.id == targetAssistantMessageID }) {
                reloadRow(row)
            } else {
                tableView.reloadData()
            }
        } else {
            // 普通新消息：先插入本地占位消息，避免首个分片在占位消息插入前到达。
            let placeholder = ChatMessage(role: .assistant, content: "")
            activeVersionMutation = nil
            streamingMessageID = placeholder.id
            session.messages.append(placeholder)
            insertLastRow()
        }

        if provider.useStream {
            ChatAPIService.shared.streamDelegate = self
            ChatAPIService.shared.sendStream(messages: requestMessages,
                                             config: provider,
                                             apiKey: key,
                                             options: currentOptions)
        } else {
            sendNonStreaming(messages: requestMessages,
                             provider: provider,
                             key: key)
        }
    }

    private func sendNonStreaming(messages: [ChatMessage], provider: ProviderConfig, key: String) {
        let startTime = streamStartTime ?? Date()
        ChatAPIService.shared.send(messages: messages,
                                   config: provider, apiKey: key,
                                   options: currentOptions) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let apiResult):
                switch apiResult.kind {
                case .message(let content, let thinking):
                    if content.isEmpty && (thinking ?? "").isEmpty {
                        self.presentGenerationErrorAsAssistant(
                            L("模型返回了空回复，请检查 API 配置、模型设置或服务端状态。",
                              "The model returned an empty reply. Please check the API config, model settings, or server status."),
                            model: apiResult.model
                        )
                        return
                    }
                    let elapsed = Date().timeIntervalSince(startTime)
                    // 找到占位消息，就地更新内容（替换打字动画）；找不到则兜底追加
                    if let sid = self.streamingMessageID,
                       let idx = self.session.messages.firstIndex(where: { $0.id == sid }) {
                        self.session.messages[idx].content        = content
                        self.session.messages[idx].thinkingContent = thinking
                        self.session.messages[idx].modelName      = apiResult.model
                        self.session.messages[idx].elapsedSeconds = elapsed
                        self.session.messages[idx].tokenUsage     = apiResult.usage
                        self.session.messages[idx].toolCallsJSON  = nil
                        self.session.updatedAt = Date()
                        if let row = self.session.visibleMessages.firstIndex(where: { $0.id == sid }) {
                            self.reloadRow(row)
                        } else {
                            self.tableView.reloadData()
                        }
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
                    if let sid = self.streamingMessageID,
                       let idx = self.session.messages.firstIndex(where: { $0.id == sid }) {
                        self.session.messages[idx].modelName = apiResult.model
                        self.session.messages[idx].tokenUsage = apiResult.usage
                        if let data = try? JSONSerialization.data(withJSONObject: calls),
                           let str = String(data: data, encoding: .utf8) {
                            self.session.messages[idx].toolCallsJSON = str
                        }
                    }
                    self.tableView.reloadData()
                    self.handleToolCalls(calls,
                                         model: apiResult.model,
                                         startTime: startTime,
                                         targetAssistantMessageID: self.streamingMessageID)
                }

            case .failure(let err):
                self.presentGenerationErrorAsAssistant(err.localizedDescription)
            }
        }
    }

    // MARK: - Tool call execution

    private func handleToolCalls(_ calls: [[String: Any]],
                                 model: String?,
                                 startTime: Date,
                                 targetAssistantMessageID: String?) {
        if targetAssistantMessageID == nil {
            var toolCallMsg = ChatMessage(role: .assistant, content: "")
            toolCallMsg.modelName = model
            if let data = try? JSONSerialization.data(withJSONObject: calls),
               let str  = String(data: data, encoding: .utf8) {
                toolCallMsg.toolCallsJSON = str
            }
            session.messages.append(toolCallMsg)
        }

        guard let sp = selectedSearchProvider else {
            presentGenerationErrorAsAssistant(
                L("当前回复需要搜索能力，但你尚未启用搜索服务。",
                  "This reply requires web search, but no search service is enabled."),
                model: model
            )
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
                        if content.isEmpty && (thinking ?? "").isEmpty {
                            self.presentGenerationErrorAsAssistant(
                                L("模型返回了空回复，请检查 API 配置、模型设置或服务端状态。",
                                  "The model returned an empty reply. Please check the API config, model settings, or server status."),
                                model: apiResult.model
                            )
                            return
                        }
                        let elapsed = Date().timeIntervalSince(startTime)
                        if let targetAssistantMessageID,
                           let idx = self.session.messages.firstIndex(where: { $0.id == targetAssistantMessageID }) {
                            self.session.messages[idx].content = content
                            self.session.messages[idx].thinkingContent = thinking
                            self.session.messages[idx].modelName = apiResult.model
                            self.session.messages[idx].elapsedSeconds = elapsed
                            self.session.messages[idx].tokenUsage = apiResult.usage
                            self.session.messages[idx].toolCallsJSON = nil
                        } else {
                            var reply = ChatMessage(role: .assistant, content: content)
                            reply.thinkingContent = thinking
                            reply.modelName       = apiResult.model
                            reply.elapsedSeconds  = elapsed
                            reply.tokenUsage      = apiResult.usage
                            self.session.messages.append(reply)
                        }
                        self.session.updatedAt = Date()
                        let shouldFollowBottom = self.isNearBottom()
                        self.tableView.reloadData()
                        if shouldFollowBottom {
                            self.scrollToBottom(animated: true)
                        }
                        self.finishGeneration()
                        self.tryGenerateTitle()
                    } else {
                        self.presentGenerationErrorAsAssistant(
                            L("暂不支持连续工具调用。",
                              "Nested tool calls are not supported yet."),
                            model: apiResult.model
                        )
                    }
                case .failure(let err):
                    self.presentGenerationErrorAsAssistant(err.localizedDescription, model: model)
                }
            }
        }
    }

    private func finishGeneration() {
        resetStreamRenderingState()
        isGenerating = false
        inputBar.setGenerating(false)
        session.updatedAt = Date()
        SessionStore.shared.save(session)
        activeVersionMutation = nil
        streamingMessageID = nil
        streamStartTime    = nil
        // Re-render last cell so cursor "▌" is removed now that isGenerating is false
        reloadLastRow()
    }

    // MARK: - Auto title

    private func tryGenerateTitle() {
        guard AppLanguage.isDefaultSessionTitle(session.title) else { return }
        let userMsgs = session.messages.filter { $0.role == .user  && !$0.isError }
        let botMsgs  = session.messages.filter { $0.role == .assistant && !$0.isError && $0.toolCallsJSON == nil }
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
        let regenerate = UIAlertAction(title: L("重新生成最后一条回复", "Regenerate Last Reply"),
                                       style: .default) { [weak self] _ in
            self?.regenerateLastAssistantReply()
        }
        regenerate.isEnabled = !isGenerating && latestRegeneratableAssistantMessageID != nil
        sheet.addAction(regenerate)
        sheet.addAction(UIAlertAction(title: L("重新生成标题", "Regenerate Title"), style: .default) { [weak self] _ in
            self?.regenerateTitle()
        })
        let editLast = UIAlertAction(title: L("编辑最后一条消息", "Edit Last Message"), style: .default) { [weak self] _ in
            self?.editLastMessage()
        }
        editLast.isEnabled = !isGenerating && latestEditableUserMessageID != nil
        sheet.addAction(editLast)
        let clearMessages = UIAlertAction(title: L("清空消息", "Clear Messages"), style: .destructive) { [weak self] _ in
            self?.clearMessages()
        }
        clearMessages.isEnabled = !isGenerating
        sheet.addAction(clearMessages)
        sheet.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func regenerateLastAssistantReply() {
        syncSessionStateFromManager(reloadTable: false)
        guard !isGenerating else { return }
        guard ChatGenerationManager.shared.canStartOperation(for: session.id) else {
            presentBackgroundGenerationBusyAlert()
            return
        }
        guard latestRegeneratableAssistantMessageID != nil else {
            let alert = UIAlertController(title: L("无法重新生成", "Unable to Regenerate"),
                                          message: L("当前没有可重新生成的 AI 回复",
                                                     "There is no AI reply available to regenerate right now."),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L("好", "OK"), style: .default))
            present(alert, animated: true)
            return
        }

        guard ChatGenerationManager.shared.regenerateLastAssistantReply(in: session,
                                                                        options: currentOptions,
                                                                        searchProvider: selectedSearchProvider) else {
            return
        }
        syncSessionStateFromManager()
    }

    /// 无论当前标题是什么，强制重新调用 AI 生成标题
    private func regenerateTitle() {
        let userMsgs = session.messages.filter { $0.role == .user && !$0.isError }
        let botMsgs  = session.messages.filter {
            $0.role == .assistant && !$0.isError && $0.toolCallsJSON == nil && !$0.content.isEmpty
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
        guard let userID = latestEditableUserMessageID else { return }
        editUserMessage(withID: userID)
    }

    private func editUserMessage(withID messageID: String) {
        syncSessionStateFromManager(reloadTable: false)
        guard let last = session.messages.first(where: { $0.id == messageID && $0.role == .user && !$0.isError }) else {
            return
        }
        let a = UIAlertController(title: L("编辑消息", "Edit Message"), message: nil, preferredStyle: .alert)
        a.addTextField { tf in tf.text = last.content }
        a.addAction(UIAlertAction(title: L("取消", "Cancel"), style: .cancel))
        a.addAction(UIAlertAction(title: L("重发", "Resend"), style: .default) { [weak self] _ in
            guard let self = self,
                  let text = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }
            guard ChatGenerationManager.shared.canStartOperation(for: self.session.id) else {
                self.presentBackgroundGenerationBusyAlert()
                return
            }
            guard ChatGenerationManager.shared.editUserMessage(in: self.session,
                                                               messageID: last.id,
                                                               newText: text,
                                                               options: self.currentOptions,
                                                               searchProvider: self.selectedSearchProvider) else {
                return
            }
            self.syncSessionStateFromManager()
        })
        present(a, animated: true)
    }

    private func clearMessages() {
        session.messages = session.messages.filter { $0.role == .system }
        session.updatedAt = Date()
        SessionStore.shared.save(session)
        tableView.reloadData()
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
        let isStreamingMessage = isGenerating && msg.id == streamingMessageID
        let isExpanded = thinkingExpandedIDs.contains(msg.id)
        let currentPage = currentPage(for: msg)
        let isLatestPage = currentPage == msg.latestPageIndex
        let canRegenerate = !isGenerating && isLatestPage && msg.id == latestRegeneratableAssistantMessageID
        let canEditMessage = !isGenerating && isLatestPage && msg.id == latestEditableUserMessageID
        let displayVersion = msg.version(at: currentPage)
        cell.configure(with: msg,
                       displayVersion: displayVersion,
                       currentPage: currentPage,
                       pageCount: msg.pageCount,
                       isGenerating: isStreamingMessage && msg.role == .assistant,
                       isThinkingStreaming: isStreamingMessage && isThinkingStreaming,
                       isThinkingExpanded: isExpanded,
                       highlightQuery: highlightQuery,
                       canRegenerate: canRegenerate,
                       canEditMessage: canEditMessage)
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
        ChatGenerationManager.shared.cancelGeneration(for: session.id)
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

    func messageCellDidTapEdit(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        let msg = session.visibleMessages[ip.row]
        guard msg.id == latestEditableUserMessageID else { return }
        editUserMessage(withID: msg.id)
    }

    func messageCellDidTapRegenerate(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        let msg = session.visibleMessages[ip.row]
        guard msg.id == latestRegeneratableAssistantMessageID else { return }
        regenerateLastAssistantReply()
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
    }

    func messageCellDidTapPreviousVersion(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        guard !(isGenerating && session.visibleMessages[ip.row].id == streamingMessageID) else { return }
        stepPage(for: session.visibleMessages[ip.row].id, delta: -1)
    }

    func messageCellDidTapNextVersion(_ cell: MessageCell) {
        guard let ip = tableView.indexPath(for: cell) else { return }
        guard !(isGenerating && session.visibleMessages[ip.row].id == streamingMessageID) else { return }
        stepPage(for: session.visibleMessages[ip.row].id, delta: 1)
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
        enqueueStreamText(chunk, kind: .content)
    }

    func apiServiceDidReceiveThinkingChunk(_ chunk: String) {
        enqueueStreamText(chunk, kind: .thinking)
    }

    func apiServiceDidFinishStream(model: String?, usage: TokenUsage?) {
        if pendingStreamSegments.isEmpty {
            finalizeStreamDisplay(model: model, usage: usage)
        } else {
            pendingStreamCompletion = PendingStreamCompletion(model: model, usage: usage)
        }
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
        let shouldFollowBottom = isNearBottom()

        if pendingStreamSegments.isEmpty {
            tableView.reloadData()
            if shouldFollowBottom {
                scrollToBottom(animated: true)
            }
            handleToolCalls(calls,
                            model: model,
                            startTime: startTime,
                            targetAssistantMessageID: streamingMessageID)
        } else {
            pendingToolCallDispatch = PendingToolCallDispatch(calls: calls,
                                                             model: model,
                                                             usage: usage,
                                                             startTime: startTime)
        }
    }

    func apiServiceDidFail(_ error: Error) {
        presentGenerationErrorAsAssistant(error.localizedDescription)
    }
}
