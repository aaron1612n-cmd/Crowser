import AVFoundation
import SwiftUI
import UIKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Accent presets. One accent at a time, always.
enum AccentChoice: String, CaseIterable, Identifiable {
    case ember, moss, ochre, plum, tide, rose, signal
    var id: String { rawValue }
    var name: String {
        switch self {
        case .ember: return "Ember"
        case .moss: return "Moss"
        case .ochre: return "Ochre"
        case .plum: return "Plum"
        case .tide: return "Tide"
        case .rose: return "Rose"
        case .signal: return "Signal"
        }
    }
    var hex: UInt32 {
        switch self {
        case .ember: return 0xE2531F
        case .moss: return 0x5E8C3A
        case .ochre: return 0xC9932B
        case .plum: return 0x8E3B6E
        case .tide: return 0x2F7F86
        case .rose: return 0xD9576F
        case .signal: return 0xE8C21A
        }
    }
    /// Text/icons sitting on the accent.
    var onAccent: UInt32 { self == .signal || self == .ochre ? 0x171614 : 0xFFFFFF }
}

enum BarStyle: String, CaseIterable, Identifiable {
    case solid, outline, minimal
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum BarPosition: String, CaseIterable, Identifiable {
    case auto, top, bottom
    var id: String { rawValue }
    var name: String { self == .auto ? "Automatic" : rawValue.capitalized }
}

enum HomeChoice: String, CaseIterable, Identifiable {
    case start, site, blank
    var id: String { rawValue }
    var name: String {
        switch self {
        case .start: return "Start page"
        case .site: return "A website"
        case .blank: return "Blank"
        }
    }
}

/// Nonisolated reads of the look settings, for drawing code anywhere (Theme, Face, Motion, Haptics).
enum Look {
    private static var d: UserDefaults { .standard }
    static var accent: AccentChoice { AccentChoice(rawValue: d.string(forKey: "crowser.pref.accent") ?? "") ?? .ember }
    static var roundness: CGFloat { CGFloat(d.object(forKey: "crowser.pref.roundness") as? Double ?? 1) }
    static var textScale: CGFloat { CGFloat(d.object(forKey: "crowser.pref.textScale") as? Double ?? 1) }
    static var boldText: Bool { d.bool(forKey: "crowser.pref.boldText") }
    static var highContrast: Bool { d.bool(forKey: "crowser.pref.highContrast") }
    static var reduceMotion: Bool { d.bool(forKey: "crowser.pref.reduceMotion") }
    static var haptics: Bool { d.object(forKey: "crowser.pref.haptics") as? Bool ?? true }
    static var compact: Bool { d.bool(forKey: "crowser.pref.compact") }
    static var barStyle: BarStyle { BarStyle(rawValue: d.string(forKey: "crowser.pref.barStyle") ?? "") ?? .solid }
}

/// Every app-wide preference, saved as it changes. Model code reads `Prefs.shared`; views observe it.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var appearance: Appearance { didSet { save(appearance.rawValue, "appearance") } }
    @Published var accent: AccentChoice { didSet { save(accent.rawValue, "accent") } }
    @Published var barStyle: BarStyle { didSet { save(barStyle.rawValue, "barStyle") } }
    @Published var barPosition: BarPosition { didSet { save(barPosition.rawValue, "barPosition") } }
    /// Corner roundness multiplier, 0 (square) to 1.4 (pillowy).
    @Published var roundness: Double { didSet { save(roundness, "roundness") } }
    @Published var compact: Bool { didSet { save(compact, "compact") } }
    /// Interface text scale, 0.85 to 1.35.
    @Published var textScale: Double { didSet { save(textScale, "textScale") } }
    @Published var boldText: Bool { didSet { save(boldText, "boldText") } }
    @Published var highContrast: Bool { didSet { save(highContrast, "highContrast") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, "reduceMotion") } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }

    // MARK: Browsing

    @Published var home: HomeChoice { didSet { save(home.rawValue, "home") } }
    @Published var homeURL: String { didSet { save(homeURL, "homeURL") } }
    @Published var linksInBackground: Bool { didSet { save(linksInBackground, "linksInBackground") } }
    /// Close tabs not looked at for this many days. 0 means never.
    @Published var autoCloseDays: Int { didSet { save(autoCloseDays, "autoCloseDays") } }
    @Published var customEngine: String { didSet { save(customEngine, "customEngine") } }
    @Published var shortcuts: [SearchShortcut] { didSet { saveShortcuts() } }
    @Published var showFavorites: Bool { didSet { save(showFavorites, "showFavorites") } }
    @Published var showRecent: Bool { didSet { save(showRecent, "showRecent") } }
    @Published var swipeTabs: Bool { didSet { save(swipeTabs, "swipeTabs") } }
    /// Private tabs need Face ID (or the passcode) after Crowser has been in the background.
    @Published var lockPrivate: Bool { didSet { save(lockPrivate, "lockPrivate") } }
    /// Pause sound and video in other tabs while a game-mode tab is on screen.
    @Published var quietWhileGaming: Bool { didSet { save(quietWhileGaming, "quietWhileGaming") } }
    /// Minutes before an unused tab sleeps (0 = never). Sleeping tabs keep their history.
    @Published var sleepAfter: Int { didSet { save(sleepAfter, "sleepAfter") } }
    /// No images, fonts or video: pages load in a fraction of the time on a slow connection.
    @Published var liteMode: Bool { didSet { save(liteMode, "liteMode") } }
    /// Web audio and video keep playing in the background and picture in picture works across apps.
    @Published var backgroundAudio: Bool {
        didSet {
            save(backgroundAudio, "backgroundAudio")
            try? AVAudioSession.sharedInstance().setCategory(backgroundAudio ? .playback : .ambient, mode: backgroundAudio ? .moviePlayback : .default)
        }
    }

    // MARK: Shields (defaults for every site; each site can drop them)

    @Published var httpsOnly: Bool { didSet { save(httpsOnly, "httpsOnly") } }
    @Published var fingerprinting: Bool { didSet { save(fingerprinting, "fingerprinting") } }
    @Published var cleanLinks: Bool { didSet { save(cleanLinks, "cleanLinks") } }
    @Published var stripReferrer: Bool { didSet { save(stripReferrer, "stripReferrer") } }
    @Published var blockPopups: Bool { didSet { save(blockPopups, "blockPopups") } }
    @Published var blockAutoplay: Bool { didSet { save(blockAutoplay, "blockAutoplay") } }
    @Published var javaScript: Bool { didSet { save(javaScript, "javaScript") } }
    @Published var fraudWarnings: Bool { didSet { save(fraudWarnings, "fraudWarnings") } }
    @Published var darkPages: Bool { didSet { save(darkPages, "darkPages") } }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        func string(_ key: String) -> String? { d.string(forKey: "crowser.pref." + key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: "crowser.pref." + key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { d.object(forKey: "crowser.pref." + key) as? Double ?? fallback }

        appearance = Appearance(rawValue: string("appearance") ?? "") ?? .system
        accent = AccentChoice(rawValue: string("accent") ?? "") ?? .ember
        barStyle = BarStyle(rawValue: string("barStyle") ?? "") ?? .solid
        barPosition = BarPosition(rawValue: string("barPosition") ?? "") ?? .auto
        roundness = double("roundness", 1)
        compact = bool("compact", false)
        textScale = double("textScale", 1)
        boldText = bool("boldText", false)
        highContrast = bool("highContrast", false)
        reduceMotion = bool("reduceMotion", false)
        haptics = bool("haptics", true)

        home = HomeChoice(rawValue: string("home") ?? "") ?? .start
        homeURL = string("homeURL") ?? ""
        linksInBackground = bool("linksInBackground", true)
        autoCloseDays = d.object(forKey: "crowser.pref.autoCloseDays") as? Int ?? 0
        customEngine = string("customEngine") ?? ""
        showFavorites = bool("showFavorites", true)
        showRecent = bool("showRecent", true)
        swipeTabs = bool("swipeTabs", true)
        lockPrivate = bool("lockPrivate", false)
        liteMode = bool("liteMode", false)
        quietWhileGaming = bool("quietWhileGaming", true)
        sleepAfter = d.object(forKey: "crowser.pref.sleepAfter") as? Int ?? 30
        backgroundAudio = bool("backgroundAudio", true)
        if let data = d.data(forKey: "crowser.pref.shortcuts"),
           let saved = try? JSONDecoder().decode([SearchShortcut].self, from: data) {
            shortcuts = saved
        } else {
            shortcuts = SearchShortcut.defaults
        }

        httpsOnly = bool("httpsOnly", true)
        fingerprinting = bool("fingerprinting", true)
        cleanLinks = bool("cleanLinks", true)
        stripReferrer = bool("stripReferrer", false)
        blockPopups = bool("blockPopups", true)
        blockAutoplay = bool("blockAutoplay", false)
        javaScript = bool("javaScript", true)
        fraudWarnings = bool("fraudWarnings", true)
        darkPages = bool("darkPages", false)
    }

    var accentColor: Color { Color(uiColor: .hex(accent.hex)) }
    var onAccentColor: Color { Color(uiColor: .hex(accent.onAccent)) }

    /// Home page as a URL, when it is a website.
    var homePage: URL? {
        guard home == .site else { return nil }
        return Address.resolve(homeURL, engine: .duckDuckGo)
    }

    func resetLook() {
        appearance = .system
        accent = .ember
        barStyle = .solid
        barPosition = .auto
        roundness = 1
        compact = false
        textScale = 1
        boldText = false
        highContrast = false
        reduceMotion = false
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: "crowser.pref." + key)
    }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            defaults.set(data, forKey: "crowser.pref.shortcuts")
        }
    }
}

/// "yt cats" searches YouTube for cats. Template uses %s for the query.
struct SearchShortcut: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var keyword: String
    var name: String
    var template: String

    static let defaults: [SearchShortcut] = [
        .init(keyword: "g", name: "Google", template: "https://www.google.com/search?q=%s"),
        .init(keyword: "d", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s"),
        .init(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query=%s"),
        .init(keyword: "w", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search=%s"),
        .init(keyword: "r", name: "Reddit", template: "https://www.reddit.com/search/?q=%s"),
        .init(keyword: "gh", name: "GitHub", template: "https://github.com/search?q=%s"),
        .init(keyword: "a", name: "Amazon", template: "https://www.amazon.com/s?k=%s"),
        .init(keyword: "maps", name: "Maps", template: "https://www.google.com/maps/search/%s"),
        .init(keyword: "img", name: "Images", template: "https://duckduckgo.com/?q=%s&ia=images&iax=images"),
        .init(keyword: "tr", name: "Translate", template: "https://translate.google.com/?sl=auto&tl=en&text=%s"),
    ]

    func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }
}
