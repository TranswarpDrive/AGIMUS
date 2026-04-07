// 搜索服务适配层：对 9 种提供商统一返回格式化的纯文本结果
import Foundation

final class SearchService {
    static let shared = SearchService()
    private init() {}

    /// 执行搜索，结果格式化为供 LLM 阅读的 Markdown 文本
    func search(query: String,
                provider: SearchProvider,
                apiKey: String,
                completion: @escaping (Result<String, Error>) -> Void) {
        switch provider.type {
        case .brave:      brave(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .tavily:     tavily(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .serper:     serper(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .bing:       bing(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .exa:        exa(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .bocha:      bocha(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .metaso:     metaso(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .jina:       jina(query: query, provider: provider, apiKey: apiKey, completion: completion)
        case .duckduckgo: ddg(query: query, provider: provider, completion: completion)
        case .custom:     customSearch(query: query, provider: provider, apiKey: apiKey, completion: completion)
        }
    }

    // MARK: - Brave Search
    private func brave(query: String, provider: SearchProvider, apiKey: String,
                       completion: @escaping (Result<String, Error>) -> Void) {
        var comps = URLComponents(string: provider.endpoint)!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "count", value: "\(provider.maxResults)")]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let web = json["web"] as? [String: Any],
                  let results = web["results"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(results.prefix(provider.maxResults).map {
                ($0["title"] as? String ?? "", $0["url"] as? String ?? "", $0["description"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Tavily
    private func tavily(query: String, provider: SearchProvider, apiKey: String,
                        completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = ["api_key": apiKey, "query": query,
                                   "max_results": provider.maxResults, "include_answer": false]
        var req = URLRequest(url: URL(string: provider.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(results.prefix(provider.maxResults).map {
                ($0["title"] as? String ?? "", $0["url"] as? String ?? "", $0["content"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Serper (Google)
    private func serper(query: String, provider: SearchProvider, apiKey: String,
                        completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: provider.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["q": query, "num": provider.maxResults])
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let organic = json["organic"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(organic.prefix(provider.maxResults).map {
                ($0["title"] as? String ?? "", $0["link"] as? String ?? "", $0["snippet"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Bing
    private func bing(query: String, provider: SearchProvider, apiKey: String,
                      completion: @escaping (Result<String, Error>) -> Void) {
        var comps = URLComponents(string: provider.endpoint)!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "count", value: "\(provider.maxResults)")]
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pages = json["webPages"] as? [String: Any],
                  let value = pages["value"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(value.prefix(provider.maxResults).map {
                ($0["name"] as? String ?? "", $0["url"] as? String ?? "", $0["snippet"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Exa
    private func exa(query: String, provider: SearchProvider, apiKey: String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: provider.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query, "numResults": provider.maxResults, "useAutoprompt": true
        ])
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(results.prefix(provider.maxResults).map {
                let snippet = ($0["text"] as? String) ?? ($0["highlights"] as? [String])?.first ?? ""
                return ($0["title"] as? String ?? "", $0["url"] as? String ?? "", snippet)
            })
        }, completion: completion)
    }

    // MARK: - Bocha (博查)
    private func bocha(query: String, provider: SearchProvider, apiKey: String,
                       completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: provider.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query, "freshness": "noLimit", "count": provider.maxResults
        ])
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let pages = dataObj["webPages"] as? [String: Any],
                  let value = pages["value"] as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(value.prefix(provider.maxResults).map {
                ($0["name"] as? String ?? "", $0["url"] as? String ?? "", $0["snippet"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Metaso (秘塔)
    private func metaso(query: String, provider: SearchProvider, apiKey: String,
                        completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: provider.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query, "search_type": "search", "count": provider.maxResults
        ])
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = (json["results"] ?? json["data"]) as? [[String: Any]]
            else { throw APIError.parseError }
            return Self.format(results.prefix(provider.maxResults).map {
                ($0["title"] as? String ?? "", $0["url"] as? String ?? "",
                 $0["snippet"] as? String ?? $0["content"] as? String ?? "")
            })
        }, completion: completion)
    }

    // MARK: - Jina Search
    private func jina(query: String, provider: SearchProvider, apiKey: String,
                      completion: @escaping (Result<String, Error>) -> Void) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let urlStr = provider.endpoint.hasSuffix("/")
            ? "\(provider.endpoint)\(encoded)"
            : "\(provider.endpoint)/\(encoded)"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { completion(.failure(APIError.invalidURL)) }; return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        fetch(req, transform: { data in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["data"] as? [[String: Any]] {
                return Self.format(results.prefix(provider.maxResults).map {
                    ($0["title"] as? String ?? "", $0["url"] as? String ?? "",
                     $0["content"] as? String ?? "")
                })
            }
            return String(data: data, encoding: .utf8) ?? "No results"
        }, completion: completion)
    }

    // MARK: - DuckDuckGo (instant answer, no key)
    private func ddg(query: String, provider: SearchProvider,
                     completion: @escaping (Result<String, Error>) -> Void) {
        var comps = URLComponents(string: provider.endpoint)!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "format", value: "json"),
                            URLQueryItem(name: "no_html", value: "1")]
        let req = URLRequest(url: comps.url!)
        fetch(req, transform: { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw APIError.parseError }
            var parts: [String] = []
            if let abs = json["AbstractText"] as? String, !abs.isEmpty {
                parts.append(abs)
            }
            if let related = json["RelatedTopics"] as? [[String: Any]] {
                for t in related.prefix(provider.maxResults) {
                    if let text = t["Text"] as? String { parts.append("• \(text)") }
                }
            }
            return parts.isEmpty ? L("未找到相关结果", "No relevant results found") : parts.joined(separator: "\n\n")
        }, completion: completion)
    }

    // MARK: - Custom (POST with generic body)
    private func customSearch(query: String, provider: SearchProvider, apiKey: String,
                              completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: provider.endpoint) else {
            DispatchQueue.main.async { completion(.failure(APIError.invalidURL)) }; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query, "q": query, "num": provider.maxResults
        ])
        fetch(req, transform: { data in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["results", "data", "items", "organic"] {
                    if let arr = json[key] as? [[String: Any]] {
                        return Self.format(arr.prefix(provider.maxResults).map {
                            ($0["title"] as? String ?? $0["name"] as? String ?? "",
                             $0["url"] as? String ?? $0["link"] as? String ?? "",
                             $0["snippet"] as? String ?? $0["content"] as? String ?? "")
                        })
                    }
                }
            }
            return String(data: data, encoding: .utf8) ?? "No results"
        }, completion: completion)
    }

    // MARK: - Helpers

    /// Generic fetch + parse helper
    private func fetch(_ request: URLRequest,
                       transform: @escaping (Data) throws -> String,
                       completion: @escaping (Result<String, Error>) -> Void) {
        var req = request
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }; return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(APIError.noData)) }; return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(.failure(APIError.http(http.statusCode, msg))) }; return
            }
            do {
                let result = try transform(data)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    /// Format a list of (title, url, snippet) tuples into numbered Markdown
    private static func format(_ results: [(String, String, String)]) -> String {
        var lines: [String] = []
        for (i, item) in results.enumerated() {
            let (title, url, snippet) = item
            lines.append("[\(i + 1)] \(title)")
            if !url.isEmpty     { lines.append("URL: \(url)") }
            if !snippet.isEmpty { lines.append(snippet) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
