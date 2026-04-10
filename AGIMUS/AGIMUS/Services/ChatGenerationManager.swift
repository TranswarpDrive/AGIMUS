import Foundation

extension Notification.Name {
    static let chatGenerationManagerDidUpdate = Notification.Name("chatGenerationManagerDidUpdate")
}

struct ChatGenerationState {
    let session: ChatSession
    let isGenerating: Bool
    let streamingMessageID: String?
    let isThinkingStreaming: Bool
    let requestOptions: ChatRequestOptions?
    let selectedSearchProvider: SearchProvider?
}

final class ChatGenerationManager: NSObject {
    static let shared = ChatGenerationManager()

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

    private var activeSession: ChatSession?
    private var isGenerating = false
    private var streamingMessageID: String?
    private var streamStartTime: Date?
    private var activeVersionMutation: ActiveVersionMutation?
    private var pendingStreamSegments: [StreamDisplaySegment] = []
    private var streamDisplayTimer: Timer?
    private var pendingStreamCompletion: PendingStreamCompletion?
    private var pendingToolCallDispatch: PendingToolCallDispatch?
    private var isThinkingStreaming = false
    private var currentOptions = ChatRequestOptions()
    private var selectedSearchProvider: SearchProvider?
    private var requestProvider: ProviderConfig?
    private var requestAPIKey = ""
    private var currentOperationID = UUID()

    private override init() {
        super.init()
    }

    func state(for sessionID: String) -> ChatGenerationState? {
        if let activeSession, activeSession.id == sessionID {
            let mergedSession = mergedSessionMetadata(activeSession)
            return ChatGenerationState(session: mergedSession,
                                       isGenerating: isGenerating,
                                       streamingMessageID: streamingMessageID,
                                       isThinkingStreaming: isThinkingStreaming,
                                       requestOptions: currentOptions,
                                       selectedSearchProvider: selectedSearchProvider)
        }
        guard let stored = SessionStore.shared.get(id: sessionID) else { return nil }
        return ChatGenerationState(session: stored,
                                   isGenerating: false,
                                   streamingMessageID: nil,
                                   isThinkingStreaming: false,
                                   requestOptions: nil,
                                   selectedSearchProvider: nil)
    }

    func mergedSessions(_ base: [ChatSession]) -> [ChatSession] {
        guard let activeSession else { return base }
        var sessions = base
        let mergedActiveSession = mergedSessionMetadata(activeSession)
        if let idx = sessions.firstIndex(where: { $0.id == activeSession.id }) {
            sessions[idx] = mergedActiveSession
        } else {
            sessions.append(mergedActiveSession)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        return sessions
    }

    func canStartOperation(for sessionID: String) -> Bool {
        !isGenerating || activeSession?.id == sessionID
    }

    @discardableResult
    func send(text: String,
              in session: ChatSession,
              options: ChatRequestOptions,
              searchProvider: SearchProvider?) -> Bool {
        guard canStartOperation(for: session.id) else { return false }

        var workingSession = latestSessionSnapshot(for: session)
        workingSession.messages.append(ChatMessage(role: .user, content: text))
        workingSession.updatedAt = Date()

        beginOperation(with: workingSession, options: options, searchProvider: searchProvider)
        persistActiveSession()
        notifyUpdate()

        let requestMessages = workingSession.messages
        startGeneratingReply(with: requestMessages,
                             targetAssistantMessageID: nil,
                             userMessageIDForNewPage: nil)
        return true
    }

    @discardableResult
    func regenerateLastAssistantReply(in session: ChatSession,
                                      options: ChatRequestOptions,
                                      searchProvider: SearchProvider?) -> Bool {
        guard canStartOperation(for: session.id) else { return false }

        let workingSession = latestSessionSnapshot(for: session)
        guard let assistantID = latestRegeneratableAssistantMessageID(in: workingSession),
              let assistantIndex = workingSession.messages.firstIndex(where: { $0.id == assistantID }),
              let userIndex = workingSession.messages[..<assistantIndex].lastIndex(where: { $0.role == .user })
        else {
            return false
        }

        beginOperation(with: workingSession, options: options, searchProvider: searchProvider)
        let requestMessages = Array(workingSession.messages[...userIndex])
        startGeneratingReply(with: requestMessages,
                             targetAssistantMessageID: assistantID,
                             userMessageIDForNewPage: nil)
        return true
    }

    @discardableResult
    func editUserMessage(in session: ChatSession,
                         messageID: String,
                         newText: String,
                         options: ChatRequestOptions,
                         searchProvider: SearchProvider?) -> Bool {
        guard canStartOperation(for: session.id) else { return false }

        var workingSession = latestSessionSnapshot(for: session)
        guard let userIndex = workingSession.messages.firstIndex(where: {
            $0.id == messageID && $0.role == .user && !$0.isError
        }) else {
            return false
        }

        let assistantIndex = workingSession.messages[(userIndex + 1)..<workingSession.messages.count]
            .firstIndex(where: {
                $0.role == .assistant &&
                $0.toolCallsJSON == nil &&
                (!$0.content.isEmpty || !(($0.thinkingContent ?? "").isEmpty))
            })

        workingSession.messages[userIndex].archiveCurrentVersion()
        workingSession.messages[userIndex].content = newText
        workingSession.messages[userIndex].timestamp = Date()
        workingSession.messages[userIndex].isError = false

        if let assistantIndex {
            let userID = workingSession.messages[userIndex].id
            let assistantID = workingSession.messages[assistantIndex].id
            workingSession.messages[userIndex].linkedVersionMessageID = assistantID
            workingSession.messages[assistantIndex].linkedVersionMessageID = userID
            workingSession.updatedAt = Date()

            beginOperation(with: workingSession, options: options, searchProvider: searchProvider)
            persistActiveSession()
            notifyUpdate()

            let requestMessages = Array(workingSession.messages[...userIndex])
            startGeneratingReply(with: requestMessages,
                                 targetAssistantMessageID: assistantID,
                                 userMessageIDForNewPage: userID)
        } else {
            workingSession.updatedAt = Date()
            beginOperation(with: workingSession, options: options, searchProvider: searchProvider)
            persistActiveSession()
            notifyUpdate()
            let requestMessages = workingSession.messages
            startGeneratingReply(with: requestMessages,
                                 targetAssistantMessageID: nil,
                                 userMessageIDForNewPage: nil)
        }

        return true
    }

    func cancelGeneration(for sessionID: String? = nil) {
        guard let activeSession else { return }
        if let sessionID, activeSession.id != sessionID { return }
        currentOperationID = UUID()
        ChatAPIService.shared.cancel()
        interruptCurrentGeneration()
    }

    private func latestSessionSnapshot(for session: ChatSession) -> ChatSession {
        if let activeSession, activeSession.id == session.id {
            return activeSession
        }
        return SessionStore.shared.get(id: session.id) ?? session
    }

    private func latestRegeneratableAssistantMessageID(in session: ChatSession) -> String? {
        guard let last = session.visibleMessages.last,
              last.role == .assistant,
              last.toolCallsJSON == nil
        else { return nil }

        let hasDisplayableContent = !last.content.isEmpty || !((last.thinkingContent ?? "").isEmpty)
        return hasDisplayableContent ? last.id : nil
    }

    private func beginOperation(with session: ChatSession,
                                options: ChatRequestOptions,
                                searchProvider: SearchProvider?) {
        currentOperationID = UUID()
        resetStreamRenderingState()
        activeSession = session
        isGenerating = true
        streamingMessageID = nil
        streamStartTime = Date()
        activeVersionMutation = nil
        currentOptions = options
        currentOptions.searchTool = searchProvider
        selectedSearchProvider = searchProvider

        var provider = SettingsStore.shared.activeProvider
        if let model = session.preferredModel, !model.isEmpty {
            provider.activeModel = model
        }
        requestProvider = provider
        requestAPIKey = SettingsStore.shared.apiKey(for: provider.id)
    }

    private func notifyUpdate() {
        guard let sessionID = activeSession?.id else { return }
        NotificationCenter.default.post(name: .chatGenerationManagerDidUpdate,
                                        object: self,
                                        userInfo: ["sessionID": sessionID])
    }

    private func notifyUpdate(for sessionID: String) {
        NotificationCenter.default.post(name: .chatGenerationManagerDidUpdate,
                                        object: self,
                                        userInfo: ["sessionID": sessionID])
    }

    private func persistActiveSession() {
        guard let activeSession else { return }
        let merged = mergedSessionMetadata(activeSession)
        self.activeSession = merged
        SessionStore.shared.save(merged)
    }

    private func mergedSessionMetadata(_ session: ChatSession) -> ChatSession {
        guard let stored = SessionStore.shared.get(id: session.id) else { return session }
        var merged = session
        merged.title = stored.title
        merged.preferredModel = stored.preferredModel
        return merged
    }

    private func resetStreamRenderingState() {
        streamDisplayTimer?.invalidate()
        streamDisplayTimer = nil
        pendingStreamSegments.removeAll()
        pendingStreamCompletion = nil
        pendingToolCallDispatch = nil
        isThinkingStreaming = false
    }

    private func startGeneratingReply(with requestMessages: [ChatMessage],
                                      targetAssistantMessageID: String?,
                                      userMessageIDForNewPage: String?) {
        guard var session = activeSession,
              let provider = requestProvider
        else { return }

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
            streamingMessageID = targetAssistantMessageID
        } else {
            let placeholder = ChatMessage(role: .assistant, content: "")
            activeVersionMutation = nil
            streamingMessageID = placeholder.id
            session.messages.append(placeholder)
            session.updatedAt = Date()
        }

        activeSession = session
        persistActiveSession()
        notifyUpdate(for: session.id)

        if provider.useStream {
            ChatAPIService.shared.streamDelegate = self
            ChatAPIService.shared.sendStream(messages: requestMessages,
                                             config: provider,
                                             apiKey: requestAPIKey,
                                             options: currentOptions)
        } else {
            sendNonStreaming(messages: requestMessages,
                             provider: provider,
                             key: requestAPIKey,
                             operationID: currentOperationID,
                             sessionID: session.id)
        }
    }

    private func sendNonStreaming(messages: [ChatMessage],
                                  provider: ProviderConfig,
                                  key: String,
                                  operationID: UUID,
                                  sessionID: String) {
        let startTime = streamStartTime ?? Date()
        ChatAPIService.shared.send(messages: messages,
                                   config: provider,
                                   apiKey: key,
                                   options: currentOptions) { [weak self] result in
            guard let self = self,
                  self.isOperationCurrent(operationID, sessionID: sessionID)
            else { return }

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
                    self.applyNonStreamingMessage(content: content,
                                                  thinking: thinking,
                                                  model: apiResult.model,
                                                  usage: apiResult.usage,
                                                  elapsed: Date().timeIntervalSince(startTime))
                    self.finishGeneration()

                case .toolCalls(let calls):
                    self.storeToolCalls(calls, model: apiResult.model, usage: apiResult.usage)
                    self.notifyUpdate(for: sessionID)
                    self.handleToolCalls(calls,
                                         model: apiResult.model,
                                         startTime: startTime,
                                         targetAssistantMessageID: self.streamingMessageID,
                                         operationID: operationID)
                }

            case .failure(let error):
                self.presentGenerationErrorAsAssistant(error.localizedDescription)
            }
        }
    }

    private func applyNonStreamingMessage(content: String,
                                          thinking: String?,
                                          model: String?,
                                          usage: TokenUsage?,
                                          elapsed: TimeInterval) {
        guard var session = activeSession else { return }
        if let streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == streamingMessageID }) {
            session.messages[idx].content = content
            session.messages[idx].thinkingContent = thinking
            session.messages[idx].modelName = model
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage = usage
            session.messages[idx].toolCallsJSON = nil
        } else {
            var reply = ChatMessage(role: .assistant, content: content)
            reply.thinkingContent = thinking
            reply.modelName = model
            reply.elapsedSeconds = elapsed
            reply.tokenUsage = usage
            session.messages.append(reply)
        }
        session.updatedAt = Date()
        activeSession = session
        notifyUpdate(for: session.id)
    }

    private func storeToolCalls(_ calls: [[String: Any]], model: String?, usage: TokenUsage?) {
        guard var session = activeSession,
              let streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == streamingMessageID })
        else { return }

        session.messages[idx].modelName = model
        session.messages[idx].tokenUsage = usage
        if let data = try? JSONSerialization.data(withJSONObject: calls),
           let str = String(data: data, encoding: .utf8) {
            session.messages[idx].toolCallsJSON = str
        }
        session.updatedAt = Date()
        activeSession = session
    }

    private func handleToolCalls(_ calls: [[String: Any]],
                                 model: String?,
                                 startTime: Date,
                                 targetAssistantMessageID: String?,
                                 operationID: UUID) {
        guard var session = activeSession else { return }

        if targetAssistantMessageID == nil {
            var toolCallMsg = ChatMessage(role: .assistant, content: "")
            toolCallMsg.modelName = model
            if let data = try? JSONSerialization.data(withJSONObject: calls),
               let str = String(data: data, encoding: .utf8) {
                toolCallMsg.toolCallsJSON = str
            }
            session.messages.append(toolCallMsg)
            activeSession = session
        }

        guard let searchProvider = selectedSearchProvider else {
            presentGenerationErrorAsAssistant(
                L("当前回复需要搜索能力，但你尚未启用搜索服务。",
                  "This reply requires web search, but no search service is enabled."),
                model: model
            )
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var results: [(callId: String, result: String)] = []
        let apiKey = SettingsStore.shared.searchAPIKey(for: searchProvider.id)

        for call in calls {
            guard let callId = call["id"] as? String,
                  let fn = call["function"] as? [String: Any],
                  let name = fn["name"] as? String,
                  name == "web_search",
                  let argsStr = fn["arguments"] as? String,
                  let argsData = argsStr.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
                  let query = args["query"] as? String
            else { continue }

            group.enter()
            SearchService.shared.search(query: query, provider: searchProvider, apiKey: apiKey) { result in
                let text: String
                switch result {
                case .success(let formatted):
                    text = formatted
                case .failure(let error):
                    text = L("搜索失败: \(error.localizedDescription)",
                             "Search failed: \(error.localizedDescription)")
                }
                lock.lock()
                results.append((callId: callId, result: text))
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self,
                  self.isOperationCurrent(operationID, sessionID: session.id),
                  var latestSession = self.activeSession
            else { return }

            for result in results {
                var toolMsg = ChatMessage(role: .tool, content: result.result)
                toolMsg.toolCallId = result.callId
                latestSession.messages.append(toolMsg)
            }

            latestSession.updatedAt = Date()
            self.activeSession = latestSession
            self.notifyUpdate(for: latestSession.id)

            guard let provider = self.requestProvider else { return }
            var options = self.currentOptions
            options.searchTool = nil

            ChatAPIService.shared.send(messages: latestSession.messages,
                                       config: provider,
                                       apiKey: self.requestAPIKey,
                                       options: options) { [weak self] result in
                guard let self = self,
                      self.isOperationCurrent(operationID, sessionID: session.id)
                else { return }

                switch result {
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
                        self.applyContinuationMessage(content: content,
                                                      thinking: thinking,
                                                      model: apiResult.model,
                                                      usage: apiResult.usage,
                                                      elapsed: Date().timeIntervalSince(startTime),
                                                      targetAssistantMessageID: targetAssistantMessageID)
                        self.finishGeneration()
                    } else {
                        self.presentGenerationErrorAsAssistant(
                            L("暂不支持连续工具调用。",
                              "Nested tool calls are not supported yet."),
                            model: apiResult.model
                        )
                    }
                case .failure(let error):
                    self.presentGenerationErrorAsAssistant(error.localizedDescription, model: model)
                }
            }
        }
    }

    private func applyContinuationMessage(content: String,
                                          thinking: String?,
                                          model: String?,
                                          usage: TokenUsage?,
                                          elapsed: TimeInterval,
                                          targetAssistantMessageID: String?) {
        guard var session = activeSession else { return }

        if let targetAssistantMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == targetAssistantMessageID }) {
            session.messages[idx].content = content
            session.messages[idx].thinkingContent = thinking
            session.messages[idx].modelName = model
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage = usage
            session.messages[idx].toolCallsJSON = nil
        } else {
            var reply = ChatMessage(role: .assistant, content: content)
            reply.thinkingContent = thinking
            reply.modelName = model
            reply.elapsedSeconds = elapsed
            reply.tokenUsage = usage
            session.messages.append(reply)
        }

        session.updatedAt = Date()
        activeSession = session
        notifyUpdate(for: session.id)
    }

    private func finalizeStreamDisplay(model: String?, usage: TokenUsage?) {
        guard var session = activeSession else { return }

        if let streamingMessageID,
           let idx = session.messages.firstIndex(where: { $0.id == streamingMessageID }) {
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
                activeSession = session
                presentGenerationErrorAsAssistant(details, model: model)
                return
            }
        }

        activeSession = session
        finishGeneration()
    }

    private func hasDisplayableContent(for messageID: String?) -> Bool {
        guard let messageID,
              let message = activeSession?.messages.first(where: { $0.id == messageID })
        else { return false }
        return !message.content.isEmpty || !((message.thinkingContent ?? "").isEmpty)
    }

    private func rollbackActiveVersionMutation() {
        guard var session = activeSession,
              let mutation = activeVersionMutation
        else { return }

        if let assistantIndex = session.messages.firstIndex(where: { $0.id == mutation.assistantMessageID }) {
            session.messages[assistantIndex].restorePreviousVersion()
        }
        if let userIndex = session.messages.firstIndex(where: { $0.id == mutation.userMessageID }) {
            session.messages[userIndex].restorePreviousVersion()
        }

        session.updatedAt = Date()
        activeSession = session
        SessionStore.shared.save(session)
        notifyUpdate(for: session.id)
    }

    private func formatAssistantErrorMessage(_ details: String) -> String {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty
            ? L("发生了未知错误。", "An unknown error occurred.")
            : trimmed
        return L("请求失败\n\n\(body)", "Request failed\n\n\(body)")
    }

    private func presentGenerationErrorAsAssistant(_ details: String, model: String? = nil) {
        guard var session = activeSession else { return }

        let messageText = formatAssistantErrorMessage(details)
        let targetID = streamingMessageID
        let elapsed = streamStartTime.map { Date().timeIntervalSince($0) }

        resetStreamRenderingState()
        isGenerating = false

        if let targetID,
           let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
            session.messages[idx].content = messageText
            session.messages[idx].thinkingContent = nil
            session.messages[idx].isError = true
            session.messages[idx].toolCallsJSON = nil
            session.messages[idx].modelName = model ?? session.messages[idx].modelName ?? requestProvider?.activeModel
            session.messages[idx].elapsedSeconds = elapsed
            session.messages[idx].tokenUsage = nil
        } else {
            var reply = ChatMessage(role: .assistant, content: messageText, isError: true)
            reply.modelName = model ?? requestProvider?.activeModel
            reply.elapsedSeconds = elapsed
            session.messages.append(reply)
        }

        session.updatedAt = Date()
        SessionStore.shared.save(session)
        let sessionID = session.id
        clearOperationState()
        notifyUpdate(for: sessionID)
    }

    private func interruptCurrentGeneration() {
        guard var session = activeSession else { return }

        resetStreamRenderingState()
        if let targetID = streamingMessageID {
            if hasDisplayableContent(for: targetID) {
                if let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
                    session.messages[idx].elapsedSeconds = streamStartTime.map { Date().timeIntervalSince($0) }
                }
            } else if activeVersionMutation != nil {
                activeSession = session
                rollbackActiveVersionMutation()
                clearOperationState()
                return
            } else if let idx = session.messages.firstIndex(where: { $0.id == targetID }) {
                session.messages.remove(at: idx)
            }
        }

        session.updatedAt = Date()
        SessionStore.shared.save(session)
        let sessionID = session.id
        clearOperationState()
        notifyUpdate(for: sessionID)
    }

    private func finishGeneration() {
        guard let session = activeSession else { return }
        resetStreamRenderingState()
        isGenerating = false
        SessionStore.shared.save(session)
        let finishedSession = session
        let sessionID = session.id
        clearOperationState()
        notifyUpdate(for: sessionID)
        tryGenerateTitle(for: finishedSession)
    }

    private func clearOperationState() {
        activeVersionMutation = nil
        streamingMessageID = nil
        streamStartTime = nil
        selectedSearchProvider = nil
        requestProvider = nil
        requestAPIKey = ""
        isGenerating = false
        isThinkingStreaming = false
        currentOptions = ChatRequestOptions()
        activeSession = nil
    }

    private func enqueueStreamText(_ text: String, kind: StreamDisplaySegmentKind) {
        guard activeSession != nil, streamingMessageID != nil else { return }

        if kind == .thinking {
            isThinkingStreaming = true
            ensureThinkingPlaceholderVisible()
        }
        guard !text.isEmpty else {
            notifyUpdate()
            return
        }

        pendingStreamSegments.append(StreamDisplaySegment(kind: kind, units: text.map { String($0) }))
        startStreamDisplayTimerIfNeeded()
    }

    private func ensureThinkingPlaceholderVisible() {
        guard var session = activeSession,
              let streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == streamingMessageID })
        else { return }

        if session.messages[idx].thinkingContent == nil {
            session.messages[idx].thinkingContent = ""
            activeSession = session
            notifyUpdate(for: session.id)
        }
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
        guard var session = activeSession,
              let streamingMessageID,
              let idx = session.messages.firstIndex(where: { $0.id == streamingMessageID })
        else {
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

        session.updatedAt = Date()
        activeSession = session
        notifyUpdate(for: session.id)

        if pendingStreamSegments.isEmpty {
            completePendingStreamWorkIfPossible()
        }
    }

    private func completePendingStreamWorkIfPossible() {
        guard pendingStreamSegments.isEmpty else { return }

        streamDisplayTimer?.invalidate()
        streamDisplayTimer = nil

        if let pendingToolCallDispatch {
            self.pendingToolCallDispatch = nil
            handleToolCalls(pendingToolCallDispatch.calls,
                            model: pendingToolCallDispatch.model,
                            startTime: pendingToolCallDispatch.startTime,
                            targetAssistantMessageID: streamingMessageID,
                            operationID: currentOperationID)
            return
        }

        if let pendingStreamCompletion {
            self.pendingStreamCompletion = nil
            finalizeStreamDisplay(model: pendingStreamCompletion.model,
                                  usage: pendingStreamCompletion.usage)
        }
    }

    private func isOperationCurrent(_ operationID: UUID, sessionID: String) -> Bool {
        currentOperationID == operationID && activeSession?.id == sessionID
    }

    private func tryGenerateTitle(for session: ChatSession) {
        guard AppLanguage.isDefaultSessionTitle(session.title) else { return }
        let userMessages = session.messages.filter { $0.role == .user && !$0.isError }
        let botMessages = session.messages.filter {
            $0.role == .assistant && !$0.isError && $0.toolCallsJSON == nil
        }
        guard userMessages.count == 1,
              let firstUser = userMessages.first,
              botMessages.count >= 1,
              let firstBot = botMessages.first
        else { return }

        let titleProvider = SettingsStore.shared.effectiveTitleProvider
        let titleKey = SettingsStore.shared.apiKey(for: titleProvider.id)
        var config = titleProvider
        config.activeModel = SettingsStore.shared.effectiveTitleModel
        config.maxTokens = 60
        config.useStream = false

        let system = ChatMessage(role: .system, content: AppLanguage.titleGenerationPrompt)
        ChatAPIService.shared.sendOneshot(messages: [system, firstUser, firstBot],
                                          config: config,
                                          apiKey: titleKey) { result in
            guard case .success(let raw) = result,
                  var storedSession = SessionStore.shared.get(id: session.id)
            else { return }

            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "《", with: "")
                .replacingOccurrences(of: "》", with: "")
                .replacingOccurrences(of: "「", with: "")
                .replacingOccurrences(of: "」", with: "")
            guard !cleaned.isEmpty else { return }

            storedSession.title = cleaned
            SessionStore.shared.save(storedSession)
            self.notifyUpdate(for: storedSession.id)
        }
    }
}

extension ChatGenerationManager: ChatAPIServiceDelegate {
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
        storeToolCalls(calls, model: model, usage: usage)
        guard let sessionID = activeSession?.id else { return }

        let startTime = streamStartTime ?? Date()
        if pendingStreamSegments.isEmpty {
            notifyUpdate(for: sessionID)
            handleToolCalls(calls,
                            model: model,
                            startTime: startTime,
                            targetAssistantMessageID: streamingMessageID,
                            operationID: currentOperationID)
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
