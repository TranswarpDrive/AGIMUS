// 会话模型：包含所有消息，按 updatedAt 排序；preferredModel 覆盖 Provider 默认模型
import Foundation

struct ChatSession: Codable {
    var id: String
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var preferredModel: String?   // nil = 跟随 Provider 当前模型

    init(title: String = "新对话") {
        self.id        = UUID().uuidString
        self.title     = title
        self.messages  = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var lastUserMessage: ChatMessage? {
        messages.last(where: { $0.role == .user })
    }

    var displayTitle: String {
        // 只返回 AI 生成的标题；模型不可用时保持"新对话"，不以用户消息代替
        return title
    }

    /// 显示给用户的消息（过滤 system / tool）
    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role == .user || $0.role == .assistant }
    }
}
