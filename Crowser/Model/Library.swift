import Foundation

struct Entry: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var url: URL
    var date: Date
    /// Favorites folder (nil = not in a folder).
    var folder: String?

    init(title: String, url: URL, date: Date = Date(), folder: String? = nil) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.date = date
        self.folder = folder
    }
}

/// Bookmarks ("the roost") and history ("lately"), kept in UserDefaults.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var bookmarks: [Entry] = []
    @Published private(set) var history: [Entry] = []

    /// Folder names in your order, including empty ones.
    @Published private(set) var folders: [String] = []

    private let foldersKey = "crowser.folders"
    private let bookmarksKey = "crowser.bookmarks"
    private let historyKey = "crowser.history"
    private let historyLimit = 500

    init() {
        bookmarks = Self.load(bookmarksKey)
        history = Self.load(historyKey)
        folders = UserDefaults.standard.stringArray(forKey: foldersKey) ?? []
        for name in bookmarks.compactMap(\.folder) where !folders.contains(name) { folders.append(name) }
        seedFavoritesOnFirstRun()
    }

    // MARK: Folders

    func createFolder(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(name) else { return }
        folders.append(name)
        saveFolders()
    }

    func renameFolder(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, let index = folders.firstIndex(of: old) else { return }
        if folders.contains(new) { folders.remove(at: index) } else { folders[index] = new }
        for i in bookmarks.indices where bookmarks[i].folder == old { bookmarks[i].folder = new }
        saveFolders()
        save(bookmarks, bookmarksKey)
    }

    /// Removes the folder; its favorites stay, outside any folder.
    func deleteFolder(_ name: String) {
        folders.removeAll { $0 == name }
        for i in bookmarks.indices where bookmarks[i].folder == name { bookmarks[i].folder = nil }
        saveFolders()
        save(bookmarks, bookmarksKey)
    }

    func move(_ url: URL, toFolder folder: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.url == url }) else { return }
        bookmarks[index].folder = folder
        save(bookmarks, bookmarksKey)
    }

    private func saveFolders() {
        UserDefaults.standard.set(folders, forKey: foldersKey)
    }

    // MARK: Import

    /// Reads a bookmarks file exported from Safari, Chrome, Firefox or Edge (the shared HTML format).
    /// Returns how many new favorites were added.
    func importBookmarks(html: String) -> Int {
        var stack: [String] = []
        var pendingFolder: String?
        var added = 0
        var known = Set(bookmarks.map(\.url))
        let scanner = html.replacingOccurrences(of: "\r", with: "")
        let pattern = try? NSRegularExpression(
            pattern: #"<H3[^>]*>(.*?)</H3>|<A\s[^>]*HREF="([^"]+)"[^>]*>(.*?)</A>|<DL>|</DL>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let range = NSRange(scanner.startIndex..., in: scanner)
        pattern?.enumerateMatches(in: scanner, range: range) { match, _, _ in
            guard let match, let whole = Range(match.range, in: scanner) else { return }
            let token = scanner[whole].uppercased()
            if token == "<DL>" {
                if let folder = pendingFolder { stack.append(folder); pendingFolder = nil }
                return
            }
            if token == "</DL>" {
                if !stack.isEmpty { stack.removeLast() }
                return
            }
            if let titleRange = Range(match.range(at: 1), in: scanner) {
                pendingFolder = Self.decode(String(scanner[titleRange]))
                return
            }
            guard let linkRange = Range(match.range(at: 2), in: scanner),
                  let url = URL(string: Self.decode(String(scanner[linkRange]))),
                  url.scheme?.hasPrefix("http") == true, !known.contains(url) else { return }
            var title = ""
            if let nameRange = Range(match.range(at: 3), in: scanner) { title = Self.decode(String(scanner[nameRange])) }
            // Browsers wrap everything in a "Bookmarks bar" / "Favorites" folder; the innermost folder is the useful one.
            let folder = stack.last.flatMap { Self.wrapperFolders.contains($0.lowercased()) ? nil : $0 }
            bookmarks.append(Entry(title: title.isEmpty ? Address.display(url) : title, url: url, folder: folder))
            known.insert(url)
            if let folder, !folders.contains(folder) { folders.append(folder) }
            added += 1
        }
        if added > 0 {
            save(bookmarks, bookmarksKey)
            saveFolders()
        }
        return added
    }

    private static let wrapperFolders: Set<String> = [
        "bookmarks", "bookmarks bar", "bookmarks toolbar", "bookmarks menu", "favorites", "favourites", "favorites bar", "other bookmarks", "mobile bookmarks",
    ]

    private static func decode(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A first launch gets a handful of favorites so the start page isn't empty.
    private func seedFavoritesOnFirstRun() {
        let key = "crowser.seededFavorites"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard bookmarks.isEmpty else { return }
        let defaults: [(String, String)] = [
            ("Wikipedia", "https://en.wikipedia.org"),
            ("YouTube", "https://m.youtube.com"),
            ("Reddit", "https://www.reddit.com"),
            ("GitHub", "https://github.com"),
            ("Hacker News", "https://news.ycombinator.com"),
            ("Weather", "https://weather.com"),
        ]
        bookmarks = defaults.compactMap { title, link in URL(string: link).map { Entry(title: title, url: $0) } }
        save(bookmarks, bookmarksKey)
    }

    func removeBookmark(_ url: URL) {
        bookmarks.removeAll { $0.url == url }
        save(bookmarks, bookmarksKey)
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(title: String, url: URL) {
        if let index = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(Entry(title: title.isEmpty ? Address.display(url) : title, url: url), at: 0)
        }
        save(bookmarks, bookmarksKey)
    }

    func removeBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save(bookmarks, bookmarksKey)
    }

    func recordVisit(title: String, url: URL) {
        let name = title.isEmpty ? Address.display(url) : title
        if let first = history.first, first.url == url {
            history[0].title = name
            history[0].date = Date()
        } else {
            history.insert(Entry(title: name, url: url), at: 0)
            if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
        }
        save(history, historyKey)
    }

    func removeHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        save(history, historyKey)
    }

    func removeHistory(_ id: UUID) {
        history.removeAll { $0.id == id }
        save(history, historyKey)
    }

    func clearHistory() {
        history = []
        save(history, historyKey)
    }

    /// Recent pages with duplicates folded, newest first.
    func recent(_ limit: Int) -> [Entry] {
        var seen = Set<URL>()
        var result: [Entry] = []
        for entry in history where !seen.contains(entry.url) {
            seen.insert(entry.url)
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    /// Bookmarks and history matching a typed fragment, bookmarks first.
    func suggestions(for query: String, limit: Int = 8) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var seen = Set<URL>()
        var result: [Entry] = []
        for entry in bookmarks + history {
            guard !seen.contains(entry.url) else { continue }
            if entry.title.lowercased().contains(needle) || entry.url.absoluteString.lowercased().contains(needle) {
                seen.insert(entry.url)
                result.append(entry)
                if result.count == limit { break }
            }
        }
        return result
    }

    /// Fills an empty library with a few sample entries (used for store screenshots only).
    func seedDemo() {
        let samples: [(String, String)] = [
            ("Corvidae — Wikipedia", "https://en.wikipedia.org/wiki/Corvidae"),
            ("Hacker News", "https://news.ycombinator.com"),
            ("The Marginalian", "https://www.themarginalian.org"),
            ("Swift Forums", "https://forums.swift.org"),
        ]
        bookmarks = samples.compactMap { title, link in URL(string: link).map { Entry(title: title, url: $0) } }
        let visited: [(String, String)] = [
            ("New Caledonian crow", "https://en.wikipedia.org/wiki/New_Caledonian_crow"),
            ("Audubon Field Guide", "https://www.audubon.org/field-guide"),
            ("Low-tech Magazine", "https://solar.lowtechmagazine.com"),
        ]
        history = visited.enumerated().compactMap { index, pair in
            URL(string: pair.1).map { Entry(title: pair.0, url: $0, date: Date().addingTimeInterval(Double(-index) * 3600)) }
        }
        save(bookmarks, bookmarksKey)
        save(history, historyKey)
    }

    private func save(_ entries: [Entry], _ key: String) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(_ key: String) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
