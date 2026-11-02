import Foundation

/// Choices remembered for one website (keyed by host, without "www.").
struct SiteSetting: Codable, Equatable {
    var game = false
    var lockScroll = true
    var desktop: Bool?
    var zoom: Double?
    var allowTrackers = false
}

/// Per-site memory: game mode, desktop site, text size, tracker exceptions.
@MainActor
final class SiteSettings {
    private(set) var sites: [String: SiteSetting] = [:]
    private let storageKey = "crowser.sites"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: SiteSetting].self, from: data) {
            sites = decoded
        }
    }

    static func key(for url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func setting(for url: URL?) -> SiteSetting {
        Self.key(for: url).flatMap { sites[$0] } ?? SiteSetting()
    }

    func update(_ url: URL?, _ change: (inout SiteSetting) -> Void) {
        guard let key = Self.key(for: url) else { return }
        var setting = sites[key] ?? SiteSetting()
        change(&setting)
        sites[key] = setting == SiteSetting() ? nil : setting
        save()
    }

    var gameSites: [String] { sites.filter { $0.value.game }.map(\.key).sorted() }

    func clearAll() {
        sites = [:]
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
