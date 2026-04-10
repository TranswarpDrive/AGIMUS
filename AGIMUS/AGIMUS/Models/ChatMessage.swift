// 单条消息：支持 thinking 内容、响应元数据、工具调用
import Foundation

enum MessageRole: String, Codable {
    case system, user, assistant, tool
}

struct ChatMessageVersion: Codable {
    var content: String
    var timestamp: Date
    var isError: Bool
    var thinkingContent: String?
    var modelName: String?
    var elapsedSeconds: Double?
    var tokenUsage: TokenUsage?
    var toolCallsJSON: String?

    var metadataLine: String {
        var parts: [String] = []
        if let m = modelName { parts.append(m) }
        if let t = elapsedSeconds { parts.append(String(format: "%.1fs", t)) }
        if let u = tokenUsage, !u.displayString.isEmpty { parts.append(u.displayString) }
        return parts.joined(separator: "  ·  ")
    }
}

struct ChatMessage: Codable {
    var id: String
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isError: Bool

    // 思考/推理内容（reasoning_content 或 <think> 块）
    var thinkingContent: String?

    // 响应元数据（仅 assistant 消息）
    var modelName: String?
    var elapsedSeconds: Double?
    var tokenUsage: TokenUsage?

    // 工具调用支持
    var toolCallsJSON: String?  // assistant 消息发出 tool_calls 时的 JSON
    var toolCallId: String?     // tool 消息回复时对应的 call id
    var linkedVersionMessageID: String?
    var versions: [ChatMessageVersion]?

    init(role: MessageRole, content: String, isError: Bool = false) {
        self.id        = UUID().uuidString
        self.role      = role
        self.content   = content
        self.timestamp = Date()
        self.isError   = isError
        self.linkedVersionMessageID = nil
        self.versions  = nil
    }

    /// 单行元数据字符串（model · Xs · tokens）
    var metadataLine: String {
        currentVersion.metadataLine
    }

    var currentVersion: ChatMessageVersion {
        ChatMessageVersion(content: content,
                           timestamp: timestamp,
                           isError: isError,
                           thinkingContent: thinkingContent,
                           modelName: modelName,
                           elapsedSeconds: elapsedSeconds,
                           tokenUsage: tokenUsage,
                           toolCallsJSON: toolCallsJSON)
    }

    var allVersions: [ChatMessageVersion] {
        (versions ?? []) + [currentVersion]
    }

    var pageCount: Int {
        allVersions.count
    }

    var latestPageIndex: Int {
        max(0, pageCount - 1)
    }

    func version(at page: Int) -> ChatMessageVersion {
        let snapshots = allVersions
        let clamped = min(max(0, page), max(0, snapshots.count - 1))
        return snapshots[clamped]
    }

    mutating func archiveCurrentVersion() {
        var snapshots = versions ?? []
        snapshots.append(currentVersion)
        versions = snapshots
    }

    mutating func apply(version: ChatMessageVersion) {
        content = version.content
        timestamp = version.timestamp
        isError = version.isError
        thinkingContent = version.thinkingContent
        modelName = version.modelName
        elapsedSeconds = version.elapsedSeconds
        tokenUsage = version.tokenUsage
        toolCallsJSON = version.toolCallsJSON
    }

    mutating func prepareForNewVersion() {
        archiveCurrentVersion()
        content = ""
        timestamp = Date()
        isError = false
        thinkingContent = nil
        modelName = nil
        elapsedSeconds = nil
        tokenUsage = nil
        toolCallsJSON = nil
    }

    mutating func restorePreviousVersion() {
        guard var snapshots = versions, let last = snapshots.popLast() else { return }
        versions = snapshots.isEmpty ? nil : snapshots
        apply(version: last)
    }
}
