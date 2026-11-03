import Foundation
import Combine

/// Choices remembered for one website (keyed by host, without "www.").
struct SiteSetting: Codable, Equatable {
    var game = false
    var lockScroll = true
    var desktop: Bool?
    var zoom: Double?
    var allowTrackers = false
    /// Every protection off for this site in one switch.
    var shieldsDown = false
    /// nil follows the global setting.
    var javaScript: Bool?
    var darkPage: Bool?
    /// Your own styles and script for this site.
    var css = ""
    var js = ""
    /// Frame counter overlay (game mode).
    var fps = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try c.decodeIfPresent(Bool.self, forKey: .game) ?? false
        lockScroll = try c.decodeIfPresent(Bool.self, forKey: .lockScroll) ?? true
        desktop = try c.decodeIfPresent(Bool.self, forKey: .desktop)
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom)
        allowTrackers = try c.decodeIfPresent(Bool.self, forKey: .allowTrackers) ?? false
        shieldsDown = try c.decodeIfPresent(Bool.self, forKey: .shieldsDown) ?? false
        javaScript = try c.decodeIfPresent(Bool.self, forKey: .javaScript)
        darkPage = try c.decodeIfPresent(Bool.self, forKey: .darkPage)
        css = try c.decodeIfPresent(String.self, forKey: .css) ?? ""
        js = try c.decodeIfPresent(String.self, forKey: .js) ?? ""
        fps = try c.decodeIfPresent(Bool.self, forKey: .fps) ?? false
    }
}

/// Per-site memory: game mode, desktop site, text size, tracker exceptions.
@MainActor
final class SiteSettings: ObservableObject {
    @Published private(set) var sites: [String: SiteSetting] = [:]
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
    var customizedSites: [String] { sites.filter { !$0.value.css.isEmpty || !$0.value.js.isEmpty }.map(\.key).sorted() }
    var shieldsDownSites: [String] { sites.filter { $0.value.shieldsDown }.map(\.key).sorted() }
    var allSites: [String] { sites.keys.sorted() }

    func remove(_ key: String) {
        sites[key] = nil
        save()
    }

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
