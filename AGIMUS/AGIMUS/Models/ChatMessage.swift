// 单条消息：支持 thinking 内容、响应元数据、工具调用
import Foundation

enum MessageRole: String, Codable {
    case system, user, assistant, tool
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

    init(role: MessageRole, content: String, isError: Bool = false) {
        self.id        = UUID().uuidString
        self.role      = role
        self.content   = content
        self.timestamp = Date()
        self.isError   = isError
    }

    /// 单行元数据字符串（model · Xs · tokens）
    var metadataLine: String {
        var parts: [String] = []
        if let m = modelName { parts.append(m) }
        if let t = elapsedSeconds { parts.append(String(format: "%.1fs", t)) }
        if let u = tokenUsage, !u.displayString.isEmpty { parts.append(u.displayString) }
        return parts.joined(separator: "  ·  ")
    }
}
