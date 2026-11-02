import Foundation

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case startpage
    case bing
    case custom

    static let storageKey = "crowser.engine"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .startpage: return "Startpage"
        case .bing: return "Bing"
        case .custom: return "Custom"
        }
    }

    private var base: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/"
        case .google: return "https://www.google.com/search"
        case .startpage: return "https://www.startpage.com/do/search"
        case .bing: return "https://www.bing.com/search"
        case .custom: return "https://duckduckgo.com/"
        }
    }

    func url(for query: String) -> URL? {
        if self == .custom {
            let template = UserDefaults.standard.string(forKey: "crowser.pref.customEngine") ?? ""
            if template.contains("%s") {
                return SearchShortcut(keyword: "", name: "", template: template).url(for: query)
            }
        }
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

        if let (shortcut, query) = shortcut(in: text) { return shortcut.url(for: query) }

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

    /// "yt lofi" → (YouTube, "lofi"). Also accepts "!yt lofi".
    static func shortcut(in text: String) -> (SearchShortcut, String)? {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var word = parts[0].lowercased()
        if word.hasPrefix("!") { word.removeFirst() }
        let query = parts[1].trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let match = shortcuts.first(where: { $0.keyword.lowercased() == word }) else { return nil }
        return (match, query)
    }

    static var shortcuts: [SearchShortcut] {
        guard let data = UserDefaults.standard.data(forKey: "crowser.pref.shortcuts"),
              let saved = try? JSONDecoder().decode([SearchShortcut].self, from: data) else { return SearchShortcut.defaults }
        return saved
    }

    private static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid",
        "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "twclid", "ttclid", "si", "ref_src",
    ]

    /// Removes tracking parameters (utm_*, fbclid, gclid…) from a link. Returns nil when nothing changed.
    static func cleaned(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return nil }
        let host = url.host ?? ""
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") { return false }
            // YouTube's "si" share id is tracking; elsewhere "si" can mean something.
            if name == "si" { return !(host.contains("youtu")) }
            return !trackingParams.contains(name)
        }
        guard kept.count != items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
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
