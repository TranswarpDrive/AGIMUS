// 网络层：chat/completions（非流式+SSE流式）/ thinking / tool calls / /models 拉取
import Foundation

// MARK: - Result types

struct ChatAPIResult {
    enum Kind {
        case message(content: String, thinking: String?)
        case toolCalls([[String: Any]])
    }
    let kind: Kind
    let model: String?
    let usage: TokenUsage?
}

struct ChatRequestOptions {
    var thinkingEnabled: Bool     = false
    var thinkingBudget: Int       = 8000
    var searchTool: SearchProvider? = nil
}

// MARK: - Delegate

protocol ChatAPIServiceDelegate: AnyObject {
    func apiServiceDidReceiveContentChunk(_ chunk: String)
    func apiServiceDidReceiveThinkingChunk(_ chunk: String)
    func apiServiceDidFinishStream(model: String?, usage: TokenUsage?)
    func apiServiceDidReceiveToolCalls(_ calls: [[String: Any]], model: String?, usage: TokenUsage?)
    func apiServiceDidFail(_ error: Error)
}

// MARK: - Error

enum APIError: LocalizedError {
    case invalidURL, encodingError, noData, parseError
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "无效的 Base URL"
        case .encodingError:      return "请求编码失败"
        case .noData:             return "未收到数据"
        case .parseError:         return "响应解析失败"
        case .http(let c, let m): return "HTTP \(c): \(m)"
        }
    }
}

// MARK: - Service

final class ChatAPIService: NSObject {
    static let shared = ChatAPIService()
    weak var streamDelegate: ChatAPIServiceDelegate?

    private var currentTask: URLSessionDataTask?
    private var debugStreamSummaries: [String] = []
    private(set) var debugLastStreamSummary = ""

    // Stream state
    private var lineBuffer = ""
    private var rawStreamData = Data()
    private var eventDataLines: [String] = []
    private var streamModel: String?
    private var streamUsage: TokenUsage?
    private var pendingToolCalls: [Int: [String: Any]] = [:]
    private var streamDoneDispatched = false   // 防止 [DONE] 丢失时 didCompleteWithError 重复触发
    private var sawStructuredPayload = false   // 已识别到 SSE/JSON 流负载
    // <think> tag parsing state
    private enum ContentMode { case normal, thinking }
    private var contentMode = ContentMode.normal
    private var tagBuffer   = ""   // buffers partial "<think>" or "</think>"

    private lazy var streamSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        streamDoneDispatched = true   // 取消后不再触发 finish 回调
        resetStreamState()
    }

    // MARK: - Non-streaming

    func send(messages: [ChatMessage],
              config: ProviderConfig,
              apiKey: String,
              options: ChatRequestOptions = ChatRequestOptions(),
              completion: @escaping (Result<ChatAPIResult, Error>) -> Void) {
        guard let req = makeRequest(messages: messages, config: config, apiKey: apiKey,
                                    stream: false, options: options)
        else { completion(.failure(APIError.encodingError)); return }

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            let result = Self.parseAPIResult(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }
        currentTask = task
        task.resume()
    }

    // MARK: - Streaming

    func sendStream(messages: [ChatMessage],
                    config: ProviderConfig,
                    apiKey: String,
                    options: ChatRequestOptions = ChatRequestOptions()) {
        guard let req = makeRequest(messages: messages, config: config, apiKey: apiKey,
                                    stream: true, options: options)
        else { streamDelegate?.apiServiceDidFail(APIError.encodingError); return }
        streamDoneDispatched = false
        debugStreamSummaries.removeAll()
        debugLastStreamSummary = ""
        resetStreamState()
        let task = streamSession.dataTask(with: req)
        currentTask = task
        task.resume()
    }

    // MARK: - One-shot (title gen, does not touch currentTask)

    func sendOneshot(messages: [ChatMessage],
                     config: ProviderConfig,
                     apiKey: String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        guard let req = makeRequest(messages: messages, config: config, apiKey: apiKey,
                                    stream: false, options: ChatRequestOptions())
        else { completion(.failure(APIError.encodingError)); return }
        URLSession.shared.dataTask(with: req) { data, response, error in
            let r = Self.parseAPIResult(data: data, response: response, error: error)
            DispatchQueue.main.async {
                switch r {
                case .success(let res):
                    if case .message(let c, _) = res.kind { completion(.success(c)) }
                    else { completion(.failure(APIError.parseError)) }
                case .failure(let e): completion(.failure(e))
                }
            }
        }.resume()
    }

    // MARK: - Fetch models

    func fetchModels(baseURL: String, apiKey: String,
                     completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/models")
        else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            guard let data = data else { DispatchQueue.main.async { completion(.failure(APIError.noData)) }; return }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(.failure(APIError.http(http.statusCode, msg))) }; return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]]
            else { DispatchQueue.main.async { completion(.failure(APIError.parseError)) }; return }
            let ids = arr.compactMap { $0["id"] as? String }.sorted()
            DispatchQueue.main.async { completion(.success(ids)) }
        }.resume()
    }

    // MARK: - Build request

    private func makeRequest(messages: [ChatMessage], config: ProviderConfig,
                             apiKey: String, stream: Bool,
                             options: ChatRequestOptions) -> URLRequest? {
        let urlStr = config.baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions"
        guard let url = URL(string: urlStr),
              let body = buildBody(messages: messages, config: config,
                                   stream: stream, options: options)
        else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        req.httpBody = body
        req.timeoutInterval = stream ? 300 : 120
        return req
    }

    private func buildBody(messages: [ChatMessage], config: ProviderConfig,
                           stream: Bool, options: ChatRequestOptions) -> Data? {
        let msgArray: [[String: Any]] = messages.filter { !$0.isError }.compactMap { msg in
            switch msg.role {
            case .system, .user:
                return ["role": msg.role.rawValue, "content": msg.content]
            case .assistant:
                if let tcJSON = msg.toolCallsJSON,
                   let tcData = tcJSON.data(using: .utf8),
                   let tc = try? JSONSerialization.jsonObject(with: tcData) {
                    return ["role": "assistant", "content": NSNull(), "tool_calls": tc]
                }
                return ["role": "assistant", "content": msg.content]
            case .tool:
                return ["role": "tool", "content": msg.content,
                        "tool_call_id": msg.toolCallId ?? ""]
            }
        }

        var body: [String: Any] = [
            "model":       config.activeModel,
            "messages":    msgArray,
            "temperature": config.temperature,
            "stream":      stream
        ]
        if config.maxTokens > 0 { body["max_tokens"] = config.maxTokens }

        // Thinking parameter (Claude-style extended thinking / some OpenAI-compat providers)
        if options.thinkingEnabled {
            body["thinking"] = ["type": "enabled", "budget_tokens": options.thinkingBudget]
        }

        // Web search tool definition
        if let _ = options.searchTool {
            body["tools"] = [webSearchToolDef()]
            body["tool_choice"] = "auto"
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    private func webSearchToolDef() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": "web_search",
                "description": "Search the web for real-time information. Use this whenever the user asks about current events, recent data, or anything you may not know.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "The search query"]
                    ],
                    "required": ["query"]
                ]
            ]
        ]
    }

    // MARK: - Parse non-stream response

    private static func parseAPIResult(data: Data?, response: URLResponse?,
                                       error: Error?) -> Result<ChatAPIResult, Error> {
        if let error = error { return .failure(error) }
        guard let data = data else { return .failure(APIError.noData) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            return .failure(APIError.http(http.statusCode, msg))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { return .failure(APIError.parseError) }

        let modelName = json["model"] as? String
        let usage     = parseUsage(json["usage"] as? [String: Any])

        // Tool calls?
        if let tc = message["tool_calls"] as? [[String: Any]] {
            return .success(ChatAPIResult(kind: .toolCalls(tc), model: modelName, usage: usage))
        }

        // Support both plain-string content and array content blocks:
        // {"content": "hello"} (OpenAI)  OR  {"content": [{"type":"text","text":"hello"}]} (some proxies)
        let content: String
        if let s = message["content"] as? String {
            content = s
        } else if let blocks = message["content"] as? [[String: Any]] {
            content = blocks.compactMap { $0["text"] as? String }.joined()
        } else {
            content = ""
        }
        let thinking = message["reasoning_content"] as? String

        // Detect <think>…</think> in content
        let (cleanContent, extractedThinking) = extractThinkTags(from: content)
        let finalThinking = thinking ?? (extractedThinking.isEmpty ? nil : extractedThinking)

        return .success(ChatAPIResult(kind: .message(content: cleanContent, thinking: finalThinking),
                                      model: modelName, usage: usage))
    }

    private static func parseUsage(_ raw: [String: Any]?) -> TokenUsage? {
        guard let u = raw else { return nil }
        return TokenUsage(promptTokens:     u["prompt_tokens"]     as? Int,
                          completionTokens: u["completion_tokens"] as? Int,
                          totalTokens:      u["total_tokens"]      as? Int)
    }

    /// Strip <think>…</think> tags from content, return (cleaned, thinking)
    private static func extractThinkTags(from text: String) -> (String, String) {
        guard text.contains("<think>") else { return (text, "") }
        var thinking = ""
        var clean    = text
        while let start = clean.range(of: "<think>"),
              let end   = clean.range(of: "</think>") {
            thinking += String(clean[start.upperBound..<end.lowerBound])
            clean.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), thinking)
    }

    // MARK: - SSE parsing

    private func resetStreamState() {
        lineBuffer = ""
        rawStreamData = Data()
        eventDataLines.removeAll()
        streamModel = nil
        streamUsage = nil
        pendingToolCalls.removeAll()
        sawStructuredPayload = false
        contentMode = .normal
        tagBuffer   = ""
    }

    private func updateDebugStreamSummary(_ label: String, payload: String) {
        let compact = payload
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let preview = compact.count > 500 ? String(compact.prefix(500)) + "…" : compact
        let entry = "\(label): \(preview)"
        debugStreamSummaries.append(entry)
        if debugStreamSummaries.count > 12 {
            debugStreamSummaries.removeFirst(debugStreamSummaries.count - 12)
        }
        debugLastStreamSummary = debugStreamSummaries.joined(separator: "\n")
        #if DEBUG
        print("[AGIMUS Stream] \(entry)")
        #endif
    }

    private func processSSEData(_ data: Data) {
        rawStreamData.append(data)
        guard let text = String(data: data, encoding: .utf8) else { return }
        lineBuffer += text
        while let range = lineBuffer.range(of: "\n") {
            var line = String(lineBuffer[lineBuffer.startIndex..<range.lowerBound])
            lineBuffer = String(lineBuffer[range.upperBound...])
            // 兼容 \r\n 行尾（部分服务商使用此格式）
            if line.hasSuffix("\r") { line.removeLast() }
            handleStreamLine(line)
        }
    }

    private func flushPendingStreamBuffer() {
        guard !lineBuffer.isEmpty else { return }
        var line = lineBuffer
        lineBuffer = ""
        if line.hasSuffix("\r") { line.removeLast() }
        handleStreamLine(line)
    }

    private func handleStreamLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // SSE event boundary
        if trimmed.isEmpty {
            flushPendingEventData()
            return
        }

        // 标准 SSE / 宽松兼容 "data:" 与 "data: "
        if line.hasPrefix("data:") {
            var payload = String(line.dropFirst(5))
            if payload.hasPrefix(" ") { payload.removeFirst() }
            eventDataLines.append(payload)
            return
        }

        // 其他 SSE 控制行，直接忽略
        if line.hasPrefix("event:") || line.hasPrefix("id:") || line.hasPrefix(":") {
            return
        }

        // 若前面已经开始积累 SSE data 行，这里把非标准续行也并进去
        if !eventDataLines.isEmpty {
            eventDataLines.append(line)
            return
        }

        // 一些服务端直接返回逐行 JSON，而不是 SSE
        processStreamPayload(trimmed)
    }

    private func flushPendingEventData() {
        guard !eventDataLines.isEmpty else { return }
        let payload = eventDataLines.joined(separator: "\n")
        eventDataLines.removeAll()
        processStreamPayload(payload)
    }

    private func processStreamPayload(_ rawPayload: String) {
        let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        sawStructuredPayload = true
        updateDebugStreamSummary("payload", payload: payload)

        if payload == "[DONE]" {
            handleStreamDone()
            return
        }

        guard !payload.isEmpty,
              let data    = payload.data(using: .utf8),
              let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            updateDebugStreamSummary("non-json payload", payload: payload)
            return
        }

        if !handleResponsesStyleEvent(json) {
            guard let choices = json["choices"] as? [[String: Any]],
                  let choice  = choices.first
            else {
                updateDebugStreamSummary("json without choices", payload: payload)
                return
            }

            if let m = json["model"] as? String, streamModel == nil { streamModel = m }
            if let u = json["usage"] as? [String: Any] { streamUsage = Self.parseUsage(u) }

            // 兼容 "delta"（标准 SSE）和 "message"（部分厂商在流式模式下也用 message 字段）
            let deltaDict = choice["delta"] as? [String: Any] ?? choice["message"] as? [String: Any]
            if let delta = deltaDict {
                // reasoning_content (DeepSeek R1 style)
                if let rc = extractThinkingText(from: delta), !rc.isEmpty {
                    DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(rc) }
                }
                let deltaText = extractDisplayText(from: delta)
                if !deltaText.isEmpty { routeContent(deltaText) }
                // tool_calls 累积
                if let tcArr = delta["tool_calls"] as? [[String: Any]] {
                    accumulateToolCalls(tcArr)
                }
            } else {
                let text = extractDisplayText(from: choice)
                if !text.isEmpty {
                    routeContent(text)
                }
            }

            // finish_reason
            if let reason = choice["finish_reason"] as? String, reason == "tool_calls" {
                let calls = pendingToolCalls.sorted { $0.key < $1.key }.map { $0.value }
                let m = streamModel; let u = streamUsage
                pendingToolCalls.removeAll()
                DispatchQueue.main.async {
                    self.streamDelegate?.apiServiceDidReceiveToolCalls(calls, model: m, usage: u)
                }
            }
        }
    }

    private func handleResponsesStyleEvent(_ json: [String: Any]) -> Bool {
        guard let type = json["type"] as? String else { return false }

        if let model = json["model"] as? String, streamModel == nil {
            streamModel = model
        }
        if let message = json["message"] as? [String: Any],
           let model = message["model"] as? String,
           streamModel == nil {
            streamModel = model
        }
        if let usage = json["usage"] as? [String: Any] {
            streamUsage = Self.parseUsage(usage)
        }
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            streamUsage = Self.parseUsage(usage)
        }

        if type == "response.output_text.delta",
           let delta = json["delta"] as? String,
           !delta.isEmpty {
            routeContent(delta)
            return true
        }

        if type == "response.reasoning.delta",
           let delta = json["delta"] as? String,
           !delta.isEmpty {
            DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(delta) }
            return true
        }

        if type == "content_block_delta" || type == "content_block_start" || type == "message_delta" {
            if let delta = json["delta"] as? [String: Any] {
                if let thinking = extractThinkingText(from: delta), !thinking.isEmpty {
                    DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(thinking) }
                }
                let text = extractDisplayText(from: delta)
                if !text.isEmpty { routeContent(text) }
                return true
            }
            if let block = json["content_block"] as? [String: Any] {
                if let thinking = extractThinkingText(from: block), !thinking.isEmpty {
                    DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(thinking) }
                }
                let text = extractDisplayText(from: block)
                if !text.isEmpty { routeContent(text) }
                return true
            }
        }

        if type == "message_start" {
            if let message = json["message"] as? [String: Any] {
                let text = extractDisplayText(from: message)
                if !text.isEmpty { routeContent(text) }
            }
            return true
        }

        if type == "response.completed" || type == "response.failed" ||
           type == "message_stop" {
            handleStreamDone()
            return true
        }

        if let delta = json["delta"] as? String, !delta.isEmpty {
            routeContent(delta)
            return true
        }
        if let delta = json["delta"] as? [String: Any] {
            if let thinking = extractThinkingText(from: delta), !thinking.isEmpty {
                DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(thinking) }
            }
            let text = extractDisplayText(from: delta)
            if !text.isEmpty { routeContent(text) }
            return true
        }
        return false
    }

    private func extractThinkingText(from dict: [String: Any]) -> String? {
        if let text = dict["reasoning_content"] as? String, !text.isEmpty { return text }
        if let text = dict["thinking"] as? String, !text.isEmpty { return text }
        if let delta = dict["delta"] as? [String: Any],
           let text = extractThinkingText(from: delta), !text.isEmpty { return text }
        if let block = dict["content_block"] as? [String: Any],
           let text = extractThinkingText(from: block), !text.isEmpty { return text }
        if let message = dict["message"] as? [String: Any],
           let text = extractThinkingText(from: message), !text.isEmpty { return text }
        if let blocks = dict["content"] as? [[String: Any]] {
            let joined = blocks.compactMap { block -> String? in
                if let thinking = block["thinking"] as? String, !thinking.isEmpty { return thinking }
                if let reasoning = block["reasoning_content"] as? String, !reasoning.isEmpty { return reasoning }
                if let text = extractThinkingText(from: block), !text.isEmpty { return text }
                return nil
            }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private func extractDisplayText(from dict: [String: Any]) -> String {
        if let s = dict["content"] as? String { return s }
        if let s = dict["text"] as? String { return s }
        if let s = dict["delta"] as? String { return s }
        if let s = dict["output_text"] as? String { return s }
        if let delta = dict["delta"] as? [String: Any] {
            let text = extractDisplayText(from: delta)
            if !text.isEmpty { return text }
        }
        if let block = dict["content_block"] as? [String: Any] {
            let text = extractDisplayText(from: block)
            if !text.isEmpty { return text }
        }
        if let message = dict["message"] as? [String: Any] {
            let text = extractDisplayText(from: message)
            if !text.isEmpty { return text }
        }
        if let textObj = dict["text"] as? [String: Any] {
            if let value = textObj["value"] as? String { return value }
            if let value = textObj["text"] as? String { return value }
        }
        if let parts = dict["parts"] as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                let text = extractDisplayText(from: part)
                return text.isEmpty ? nil : text
            }.joined()
            if !joined.isEmpty { return joined }
        }
        if let blocks = dict["content"] as? [[String: Any]] {
            return blocks.compactMap { block in
                if let text = block["text"] as? String, !text.isEmpty { return text }
                if let text = block["content"] as? String, !text.isEmpty { return text }
                if let text = block["delta"] as? String, !text.isEmpty { return text }
                if let textObj = block["text"] as? [String: Any] {
                    if let value = textObj["value"] as? String, !value.isEmpty { return value }
                    if let value = textObj["text"] as? String, !value.isEmpty { return value }
                }
                return nil
            }.joined()
        }
        return ""
    }

    /// 处理 [DONE]：标记完成、触发回调、清理状态
    private func handleStreamDone() {
        streamDoneDispatched = true
        if pendingToolCalls.isEmpty {
            let m = streamModel; let u = streamUsage
            DispatchQueue.main.async { self.streamDelegate?.apiServiceDidFinishStream(model: m, usage: u) }
        }
        resetStreamState()
    }

    /// Route content chunks, splitting on <think> / </think> tags
    private func routeContent(_ chunk: String) {
        var remaining = chunk
        while !remaining.isEmpty {
            switch contentMode {
            case .normal:
                if let r = remaining.range(of: "<think>") {
                    let before = String(remaining[..<r.lowerBound])
                    if !before.isEmpty {
                        DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveContentChunk(before) }
                    }
                    remaining = String(remaining[r.upperBound...])
                    contentMode = .thinking
                } else {
                    let contentChunk = remaining
                    DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveContentChunk(contentChunk) }
                    remaining = ""
                }
            case .thinking:
                if let r = remaining.range(of: "</think>") {
                    let think = String(remaining[..<r.lowerBound])
                    if !think.isEmpty {
                        DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(think) }
                    }
                    remaining = String(remaining[r.upperBound...])
                    contentMode = .normal
                } else {
                    let thinkingChunk = remaining
                    DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(thinkingChunk) }
                    remaining = ""
                }
            }
        }
    }

    private func accumulateToolCalls(_ deltas: [[String: Any]]) {
        for delta in deltas {
            let idx = delta["index"] as? Int ?? 0
            if var existing = pendingToolCalls[idx] {
                if let fn    = delta["function"] as? [String: Any],
                   let args  = fn["arguments"] as? String {
                    var ef    = existing["function"] as? [String: Any] ?? [:]
                    ef["arguments"] = (ef["arguments"] as? String ?? "") + args
                    existing["function"] = ef
                    pendingToolCalls[idx] = existing
                }
            } else {
                pendingToolCalls[idx] = delta
            }
        }
    }

    private func dispatchNonSSEFallback(response: URLResponse?) -> Bool {
        let result = Self.parseAPIResult(data: rawStreamData, response: response, error: nil)
        guard case .success(let apiResult) = result else { return false }

        streamDoneDispatched = true
        let model = apiResult.model
        let usage = apiResult.usage

        switch apiResult.kind {
        case .message(let content, let thinking):
            if let thinking = thinking, !thinking.isEmpty {
                DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveThinkingChunk(thinking) }
            }
            if !content.isEmpty {
                DispatchQueue.main.async { self.streamDelegate?.apiServiceDidReceiveContentChunk(content) }
            }
            DispatchQueue.main.async {
                self.streamDelegate?.apiServiceDidFinishStream(model: model, usage: usage)
            }
        case .toolCalls(let calls):
            DispatchQueue.main.async {
                self.streamDelegate?.apiServiceDidReceiveToolCalls(calls, model: model, usage: usage)
            }
        }
        resetStreamState()
        return true
    }
}

extension ChatAPIService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        processSSEData(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            DispatchQueue.main.async { self.streamDelegate?.apiServiceDidFail(error) }
        } else {
            flushPendingStreamBuffer()
            flushPendingEventData()
            // 连接正常关闭。若 [DONE] 已处理则 streamDoneDispatched=true，无需重复触发。
            // 若服务器未发送 [DONE]（某些厂商省略），此处兜底触发 finish，防止 UI 卡在"生成中"。
            guard !streamDoneDispatched else { return }
            if !sawStructuredPayload, dispatchNonSSEFallback(response: task.response) { return }
            let m = streamModel; let u = streamUsage
            if pendingToolCalls.isEmpty {
                DispatchQueue.main.async { self.streamDelegate?.apiServiceDidFinishStream(model: m, usage: u) }
            }
            resetStreamState()
        }
    }
}
