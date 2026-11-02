import Foundation

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case startpage
    case bing

    static let storageKey = "crowser.engine"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .startpage: return "Startpage"
        case .bing: return "Bing"
        }
    }

    private var base: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/"
        case .google: return "https://www.google.com/search"
        case .startpage: return "https://www.startpage.com/do/search"
        case .bing: return "https://www.bing.com/search"
        }
    }

    func url(for query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .duckDuckGo
    }
}

enum Address {
    private static let webSchemes: Set<String> = ["http", "https", "about", "file", "data"]

    /// Turns whatever was typed into the bar into a URL: a full address, a bare host, or a search.
    static func resolve(_ raw: String, engine: SearchEngine = .current) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) {
            if scheme.hasPrefix("http") {
                if url.host != nil { return url }
            } else {
                return url
            }
        }

        if !text.contains(" "), looksLikeHost(text), let url = URL(string: "https://" + text), url.host != nil {
            return url
        }

        return engine.url(for: text)
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        if hostPart.hasPrefix("localhost") { return true }
        let pieces = hostPart.split(separator: ":").first?.split(separator: ".") ?? []
        guard pieces.count >= 2, let tld = pieces.last else { return false }
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Short form shown in the bar when not editing: the host without "www.".
    static func display(_ url: URL?) -> String {
        guard let url else { return "" }
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Search-as-you-type suggestions (DuckDuckGo's autocomplete endpoint, no account or key).
enum SearchSuggestions {
    private struct Phrase: Decodable { let phrase: String }

    static func fetch(_ query: String) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !trimmed.contains("://") else { return [] }
        var components = URLComponents(string: "https://duckduckgo.com/ac/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components?.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let phrases = try JSONDecoder().decode([Phrase].self, from: data)
            return phrases.map(\.phrase).filter { $0.lowercased() != trimmed.lowercased() }.prefix(5).map { $0 }
        } catch {
            return []
        }
    }
}
