// 搜索服务提供商配置：预设常见服务商 + 自定义
import Foundation

enum SearchProviderType: String, Codable, CaseIterable {
    case brave, bocha, metaso, tavily, serper, bing, exa, jina, duckduckgo, custom

    var displayName: String {
        switch self {
        case .brave:      return "Brave Search"
        case .bocha:      return L("Bocha 博查", "Bocha")
        case .metaso:     return L("Metaso 秘塔", "Metaso")
        case .tavily:     return "Tavily"
        case .serper:     return "Serper (Google)"
        case .bing:       return "Bing Web Search"
        case .exa:        return "Exa"
        case .jina:       return "Jina Search"
        case .duckduckgo: return L("DuckDuckGo（免费）", "DuckDuckGo (Free)")
        case .custom:     return L("自定义", "Custom")
        }
    }

    var legacyDisplayNames: [String] {
        switch self {
        case .brave:      return ["Brave Search"]
        case .bocha:      return ["Bocha 博查", "Bocha"]
        case .metaso:     return ["Metaso 秘塔", "Metaso"]
        case .tavily:     return ["Tavily"]
        case .serper:     return ["Serper (Google)"]
        case .bing:       return ["Bing Web Search"]
        case .exa:        return ["Exa"]
        case .jina:       return ["Jina Search"]
        case .duckduckgo: return ["DuckDuckGo（免费）", "DuckDuckGo (Free)"]
        case .custom:     return ["自定义", "Custom"]
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .brave:      return "https://api.search.brave.com/res/v1/web/search"
        case .bocha:      return "https://api.bocha.ai/search"
        case .metaso:     return "https://metaso.cn/api/secretkey"
        case .tavily:     return "https://api.tavily.com/search"
        case .serper:     return "https://google.serper.dev/search"
        case .bing:       return "https://api.bing.microsoft.com/v7.0/search"
        case .exa:        return "https://api.exa.ai/search"
        case .jina:       return "https://s.jina.ai"
        case .duckduckgo: return "https://api.duckduckgo.com"
        case .custom:     return ""
        }
    }

    var needsAPIKey: Bool { self != .duckduckgo }
}

struct SearchProvider: Codable {
    var id: String
    var type: SearchProviderType
    var name: String
    var endpoint: String
    var maxResults: Int

    init(type: SearchProviderType) {
        self.id         = UUID().uuidString
        self.type       = type
        self.name       = type.displayName
        self.endpoint   = type.defaultEndpoint
        self.maxResults = 5
    }

    var displayName: String {
        type.legacyDisplayNames.contains(name) ? type.displayName : name
    }
}
