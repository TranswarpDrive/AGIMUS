// 设置持久化：多 Provider / 搜索服务 / 标题生成配置
import Foundation

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let providersKey     = "providers_v2"
    private let activeIDKey      = "activeProviderID"
    private let promptKey        = "defaultSystemPrompt"
    private let titleProviderKey = "titleProviderID"
    private let titleModelKey    = "titleModel"
    private let searchProvsKey   = "searchProviders"
    private let appearanceKey    = "appearanceMode"   // 0=跟随系统 1=浅色 2=深色

    private init() {}

    // MARK: - Chat Providers

    var providers: [ProviderConfig] {
        get {
            guard let data = defaults.data(forKey: providersKey),
                  let arr = try? JSONDecoder().decode([ProviderConfig].self, from: data),
                  !arr.isEmpty
            else { return [.default] }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: providersKey)
            }
        }
    }

    var activeProviderID: String {
        get {
            if let saved = defaults.string(forKey: activeIDKey),
               providers.contains(where: { $0.id == saved }) { return saved }
            return providers.first?.id ?? ""
        }
        set { defaults.set(newValue, forKey: activeIDKey) }
    }

    var activeProvider: ProviderConfig {
        get { providers.first { $0.id == activeProviderID } ?? providers.first ?? .default }
        set { updateProvider(newValue) }
    }

    func updateProvider(_ provider: ProviderConfig) {
        var ps = providers
        if let idx = ps.firstIndex(where: { $0.id == provider.id }) { ps[idx] = provider }
        else { ps.append(provider) }
        providers = ps
    }

    func deleteProvider(id: String) {
        var ps = providers.filter { $0.id != id }
        if ps.isEmpty { ps = [.default] }
        providers = ps
        if activeProviderID == id { activeProviderID = ps.first?.id ?? "" }
        if titleProviderID == id  { titleProviderID = nil }
    }

    // MARK: - API Keys (Keychain per provider)

    func apiKey(for providerID: String) -> String {
        KeychainService.shared.load(forKey: "prov_\(providerID)") ?? ""
    }
    func setAPIKey(_ key: String, for providerID: String) {
        KeychainService.shared.save(key, forKey: "prov_\(providerID)")
    }

    // MARK: - Search Providers

    var searchProviders: [SearchProvider] {
        get {
            guard let data = defaults.data(forKey: searchProvsKey),
                  let arr = try? JSONDecoder().decode([SearchProvider].self, from: data)
            else { return [] }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: searchProvsKey)
            }
        }
    }

    func searchAPIKey(for providerID: String) -> String {
        KeychainService.shared.load(forKey: "search_\(providerID)") ?? ""
    }
    func setSearchAPIKey(_ key: String, for providerID: String) {
        KeychainService.shared.save(key, forKey: "search_\(providerID)")
    }

    func updateSearchProvider(_ sp: SearchProvider) {
        var arr = searchProviders
        if let idx = arr.firstIndex(where: { $0.id == sp.id }) { arr[idx] = sp }
        else { arr.append(sp) }
        searchProviders = arr
    }

    func deleteSearchProvider(id: String) {
        searchProviders = searchProviders.filter { $0.id != id }
    }

    // MARK: - Defaults

    var defaultSystemPrompt: String {
        get { defaults.string(forKey: promptKey) ?? "You are a helpful assistant." }
        set { defaults.set(newValue, forKey: promptKey) }
    }

    // MARK: - Title generation

    var titleProviderID: String? {
        get { defaults.string(forKey: titleProviderKey) }
        set {
            if let v = newValue { defaults.set(v, forKey: titleProviderKey) }
            else { defaults.removeObject(forKey: titleProviderKey) }
        }
    }
    var titleModel: String? {
        get { defaults.string(forKey: titleModelKey) }
        set {
            if let v = newValue { defaults.set(v, forKey: titleModelKey) }
            else { defaults.removeObject(forKey: titleModelKey) }
        }
    }
    var effectiveTitleProvider: ProviderConfig {
        if let id = titleProviderID, let p = providers.first(where: { $0.id == id }) { return p }
        return activeProvider
    }
    var effectiveTitleModel: String { titleModel ?? effectiveTitleProvider.activeModel }

    // MARK: - Appearance (0=跟随系统, 1=浅色, 2=深色)

    var appearanceMode: Int {
        get { defaults.integer(forKey: appearanceKey) }
        set { defaults.set(newValue, forKey: appearanceKey) }
    }
}
