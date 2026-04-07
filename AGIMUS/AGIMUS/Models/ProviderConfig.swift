// Provider 配置：支持多提供商，每个提供商独立保存 URL / Key / 模型列表 / 推理参数
import Foundation

struct ProviderConfig: Codable {
    var id: String
    var name: String
    var baseURL: String
    var models: [String]       // 已保存的模型名列表
    var activeModel: String    // 当前选中模型
    var temperature: Double
    var maxTokens: Int         // 0 = 不限制（请求时省略 max_tokens 字段）
    var useStream: Bool

    init(name: String = "新提供商",
         baseURL: String = "https://api.openai.com/v1",
         models: [String] = ["gpt-3.5-turbo"],
         activeModel: String = "gpt-3.5-turbo",
         temperature: Double = 0.7,
         maxTokens: Int = 4096,
         useStream: Bool = false) {
        self.id          = UUID().uuidString
        self.name        = name
        self.baseURL     = baseURL
        self.models      = models
        self.activeModel = activeModel
        self.temperature = temperature
        self.maxTokens   = maxTokens
        self.useStream   = useStream
    }

    static var `default`: ProviderConfig { ProviderConfig() }
}
