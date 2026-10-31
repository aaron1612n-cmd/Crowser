import SwiftUI

/// The open tabs and which one is in front.
@MainActor
final class BrowserStore: ObservableObject {
    enum Sheet: String, Identifiable {
        case tabs, library, settings
        var id: String { rawValue }
    }

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var sheet: Sheet?
    /// Bumped to ask the address bar to take focus (⌘L, new tab).
    @Published private(set) var addressFocusRequest = 0
    /// Whether the address bar is being edited, and what is typed in it.
    @Published var isEditingAddress = false
    @Published var addressDraft = ""

    let library: Library

    private let tabsKey = "crowser.tabs"
    private let selectedKey = "crowser.selectedTab"

    init(library: Library) {
        self.library = library

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "crowserSeed") { library.seedDemo() }
        if !defaults.bool(forKey: "crowserFresh") { restore() }
        // Screenshot hook: "-crowserOpen 'https://a|https://b'" opens those pages in fresh tabs.
        for link in (defaults.string(forKey: "crowserOpen") ?? "").split(separator: "|") {
            if let url = URL(string: String(link)) { newTab(url: url, focus: false) }
        }
        if tabs.isEmpty { newTab(focus: false) }
        if let sheetName = defaults.string(forKey: "crowserSheet") { sheet = Sheet(rawValue: sheetName) }
    }

    var current: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    // MARK: Tabs

    func newTab(url: URL? = nil, isPrivate: Bool = false, focus: Bool = true) {
        let tab = BrowserTab(url: url, isPrivate: isPrivate)
        wire(tab)
        tabs.append(tab)
        selectedID = tab.id
        if focus && url == nil { focusAddress() }
        persist()
    }

    func select(_ tab: BrowserTab) {
        selectedID = tab.id
        persist()
    }

    func selectAdjacent(_ step: Int) {
        guard let current, let index = tabs.firstIndex(where: { $0.id == current.id }), !tabs.isEmpty else { return }
        let next = (index + step + tabs.count) % tabs.count
        select(tabs[next])
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

    func close(at offsets: IndexSet) {
        offsets.map { tabs[$0] }.forEach { close($0) }
    }

    func closeCurrent() {
        if let current { close(current) }
    }

    func closeAll() {
        tabs.forEach { $0.stop() }
        tabs = []
        newTab(focus: false)
    }

    // MARK: Navigation

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
        isEditingAddress = false
        persist()
    }

    func focusAddress() {
        addressFocusRequest += 1
    }

    func toggleBookmarkForCurrent() {
        guard let tab = current, let url = tab.url else { return }
        library.toggleBookmark(title: tab.title, url: url)
    }

    // MARK: Persistence

    /// Saves the non-private tabs so they come back next launch.
    func persist() {
        let saved = tabs.filter { !$0.isPrivate }
        let links = saved.map { $0.url?.absoluteString ?? "" }
        let selected = saved.firstIndex { $0.id == selectedID } ?? max(0, saved.count - 1)
        UserDefaults.standard.set(links, forKey: tabsKey)
        UserDefaults.standard.set(selected, forKey: selectedKey)
    }

    private func restore() {
        let links = UserDefaults.standard.stringArray(forKey: tabsKey) ?? []
        for link in links {
            let tab = BrowserTab(url: URL(string: link))
            wire(tab)
            tabs.append(tab)
        }
        let selected = UserDefaults.standard.integer(forKey: selectedKey)
        if tabs.indices.contains(selected) { selectedID = tabs[selected].id } else { selectedID = tabs.last?.id }
    }

    private func wire(_ tab: BrowserTab) {
        tab.onVisit = { [weak self] title, url in
            self?.library.recordVisit(title: title, url: url)
            self?.persist()
        }
        tab.onOpenInNewTab = { [weak self, isPrivate = tab.isPrivate] url in
            self?.newTab(url: url, isPrivate: isPrivate, focus: false)
        }
    }
}
