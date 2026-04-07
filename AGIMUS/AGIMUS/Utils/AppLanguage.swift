import Foundation

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    static var current: AppLanguage { SettingsStore.shared.appLanguage }

    var optionLabel: String {
        switch self {
        case .chinese: return L("中文", "Chinese")
        case .english: return L("英语", "English")
        }
    }

    static var defaultSessionTitle: String { L("新对话", "New Chat") }
    static var defaultProviderName: String { L("新提供商", "New Provider") }
    static var searchDisabledLabel: String { L("关闭搜索", "Search Off") }

    static var titleGenerationPrompt: String {
        switch current {
        case .chinese:
            return "请根据以下对话内容，用不超过8个汉字生成一个简洁的中文标题。只输出标题本身，不加任何标点、引号或额外说明。"
        case .english:
            return "Based on the following conversation, generate a concise English title in no more than 6 words. Output only the title itself, with no punctuation, quotation marks, or extra explanation."
        }
    }

    static func isDefaultSessionTitle(_ value: String) -> Bool {
        value == "新对话" || value == "New Chat"
    }

    static func isDefaultProviderName(_ value: String) -> Bool {
        value == "新提供商" || value == "New Provider"
    }

    static func isSearchDisabledLabel(_ value: String) -> Bool {
        value == "关闭搜索" || value == "Search Off"
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AppLanguageDidChange")
}

@inline(__always)
func L(_ zh: String, _ en: String) -> String {
    AppLanguage.current == .english ? en : zh
}
