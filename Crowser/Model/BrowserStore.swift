import SwiftUI
import WebKit

/// The open tabs, which one is in front, and the app-wide browsing state.
@MainActor
final class BrowserStore: ObservableObject {
    enum Sheet: String, Identifiable {
        case library, settings, more
        var id: String { rawValue }
    }

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var sheet: Sheet?
    @Published var showingOverview = false
    @Published var isEditingAddress = false
    @Published var addressDraft = ""
    @Published private(set) var toast: String?

    @Published var collapseOnScroll: Bool {
        didSet { UserDefaults.standard.set(collapseOnScroll, forKey: "crowser.collapseOnScroll") }
    }
    @Published var suggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(suggestionsEnabled, forKey: "crowser.suggestions") }
    }
    @Published var blockTrackers: Bool {
        didSet {
            UserDefaults.standard.set(blockTrackers, forKey: ContentBlocker.storageKey)
            tabs.forEach { $0.setContentRules(contentRules, enabled: blockTrackers) }
        }
    }

    let library: Library
    private(set) var contentRules: WKContentRuleList?

    private let tabsKey = "crowser.tabs"
    private let selectedKey = "crowser.selectedTab"
    private var toastTask: Task<Void, Never>?

    init(library: Library) {
        self.library = library
        let defaults = UserDefaults.standard
        collapseOnScroll = defaults.object(forKey: "crowser.collapseOnScroll") as? Bool ?? true
        suggestionsEnabled = defaults.object(forKey: "crowser.suggestions") as? Bool ?? true
        blockTrackers = ContentBlocker.isEnabled

        if defaults.bool(forKey: "crowserSeed") { library.seedDemo() }
        if !defaults.bool(forKey: "crowserFresh") { restore() }
        // Screenshot hook: "-crowserOpen 'https://a|https://b'" opens those pages in fresh tabs.
        for link in (defaults.string(forKey: "crowserOpen") ?? "").split(separator: "|") {
            if let url = URL(string: String(link)) { newTab(url: url, focus: false) }
        }
        if tabs.isEmpty { newTab(focus: false) }

        Task { await loadContentRules() }
        Task { await runDemoHooks() }
    }

    var current: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    // MARK: Tabs

    func newTab(url: URL? = nil, isPrivate: Bool = false, focus: Bool = true) {
        let tab = BrowserTab(url: url, isPrivate: isPrivate, store: self)
        tabs.append(tab)
        selectedID = tab.id
        showingOverview = false
        if focus && url == nil { beginEditing() }
        persist()
    }

    func openInBackground(_ url: URL, isPrivate: Bool) {
        let tab = BrowserTab(url: url, isPrivate: isPrivate, store: self)
        if let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        showToast("Opened in new tab")
        Haptics.tap()
        persist()
    }

    /// A page asked for a new window; WebKit loads into the web view we hand back.
    func openPopup(configuration: WKWebViewConfiguration, from opener: BrowserTab) -> WKWebView {
        let tab = BrowserTab(isPrivate: opener.isPrivate, configuration: configuration, store: self)
        tab.setContentRules(contentRules, enabled: blockTrackers)
        if let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        selectedID = tab.id
        return tab.webView
    }

    func select(_ tab: BrowserTab) {
        guard tab.id != selectedID else { return }
        if let previous = current { Task { await previous.captureSnapshot() } }
        selectedID = tab.id
        Haptics.select()
        persist()
    }

    /// Steps through tabs (swipe on the bar). Swiping past the last tab opens a new one.
    func selectAdjacent(_ step: Int, createAtEnd: Bool = false) {
        guard let current, let index = tabs.firstIndex(where: { $0.id == current.id }) else { return }
        let next = index + step
        if tabs.indices.contains(next) {
            select(tabs[next])
        } else if createAtEnd && step > 0 && current.url != nil {
            Task { await current.captureSnapshot() }
            newTab(isPrivate: current.isPrivate, focus: false)
            Haptics.select()
        } else if !createAtEnd {
            select(tabs[(next + tabs.count) % tabs.count])
        }
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.stop()
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab(focus: false)
        } else if selectedID == tab.id {
            selectedID = tabs[max(0, index - 1)].id
        }
        persist()
    }

    func closeCurrent() {
        if let current { close(current) }
    }

    func closeAll(isPrivate: Bool) {
        let doomed = tabs.filter { $0.isPrivate == isPrivate }
        doomed.forEach { $0.stop() }
        tabs.removeAll { $0.isPrivate == isPrivate }
        if tabs.isEmpty { newTab(focus: false) } else if current == nil || !tabs.contains(where: { $0.id == selectedID }) {
            selectedID = tabs.last?.id
        }
        persist()
    }

    func showOverview() {
        endEditing()
        Task {
            await current?.captureSnapshot()
            withAnimation(Motion.soft) { showingOverview = true }
        }
    }

    func hideOverview() {
        withAnimation(Motion.soft) { showingOverview = false }
    }

    // MARK: Address bar

    func beginEditing() {
        addressDraft = current?.url?.absoluteString ?? ""
        withAnimation(Motion.snappy) { isEditingAddress = true }
    }

    func endEditing() {
        guard isEditingAddress else { return }
        withAnimation(Motion.snappy) { isEditingAddress = false }
    }

    /// Opens typed text (address or search) in the front tab.
    func open(_ text: String) {
        guard let url = Address.resolve(text) else { return }
        open(url)
    }

    func open(_ url: URL) {
        if let current {
            current.load(url)
        } else {
            newTab(url: url, focus: false)
        }
        endEditing()
        persist()
    }

    func toggleBookmarkForCurrent() {
        guard let tab = current, let url = tab.url else { return }
        let adding = !library.isBookmarked(url)
        library.toggleBookmark(title: tab.title, url: url)
        Haptics.tap()
        showToast(adding ? "Added to favorites" : "Removed from favorites")
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(Motion.snappy) { toast = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.soft) { toast = nil }
        }
    }

    // MARK: Content blocking

    private func loadContentRules() async {
        contentRules = await ContentBlocker.compile()
        tabs.forEach { $0.setContentRules(contentRules, enabled: blockTrackers) }
    }

    // MARK: Persistence

    /// Saves the non-private tabs so they come back next launch.
    func persist() {
        let saved = tabs.filter { !$0.isPrivate }
        let links = saved.map { ($0.webView.url ?? $0.url)?.absoluteString ?? "" }
        let selected = saved.firstIndex { $0.id == selectedID } ?? max(0, saved.count - 1)
        UserDefaults.standard.set(links, forKey: tabsKey)
        UserDefaults.standard.set(selected, forKey: selectedKey)
    }

    private func restore() {
        let links = UserDefaults.standard.stringArray(forKey: tabsKey) ?? []
        for link in links {
            tabs.append(BrowserTab(url: URL(string: link), store: self))
        }
        let selected = UserDefaults.standard.integer(forKey: selectedKey)
        selectedID = tabs.indices.contains(selected) ? tabs[selected].id : tabs.last?.id
    }

    // MARK: Screenshot hooks (launch arguments, used by CI only)

    private func runDemoHooks() async {
        let defaults = UserDefaults.standard
        guard let scene = defaults.string(forKey: "crowserScene") else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        switch scene {
        case "tabs":
            for tab in tabs {
                selectedID = tab.id
                try? await Task.sleep(nanoseconds: 700_000_000)
                await tab.captureSnapshot()
            }
            showOverview()
        case "edit":
            beginEditing()
            addressDraft = defaults.string(forKey: "crowserQuery") ?? "crow"
        case "more":
            sheet = .more
        case "collapsed":
            current?.setCollapsed(true)
        case "settings":
            sheet = .settings
        default:
            break
        }
    }
}
