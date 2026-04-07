// Token 用量 + 响应耗时，附加到每条 assistant 消息上
import Foundation

struct TokenUsage: Codable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    /// 格式化为 "↑123 ↓456 Σ579"
    var displayString: String {
        var parts: [String] = []
        if let p = promptTokens    { parts.append("↑\(p)") }
        if let c = completionTokens { parts.append("↓\(c)") }
        if let t = totalTokens      { parts.append("Σ\(t)") }
        return parts.isEmpty ? "" : parts.joined(separator: "  ")
    }
}
