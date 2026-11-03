import LocalAuthentication
import SwiftUI
import WebKit

/// The open tabs, which one is in front, and the app-wide browsing state.
@MainActor
final class BrowserStore: ObservableObject {
    enum Sheet: String, Identifiable {
        case library, settings, more, shields, siteCode, palette, qrScan, qrCode, note
        var id: String { rawValue }
    }

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var sheet: Sheet?
    @Published var showingOverview = false
    @Published var isEditingAddress = false
    @Published var addressDraft = ""
    @Published private(set) var toast: String?
    /// A toast can carry one action, like Undo.
    private(set) var toastAction: (title: String, run: () -> Void)?
    /// Tab groups, and the one the overview is showing (nil shows every tab).
    @Published private(set) var groups: [TabGroup] = []
    @Published var activeGroupID: UUID?
    @Published private(set) var sessions: [SavedSession] = []
    /// The bar is tucked away to a small ember pull tab until you bring it back.
    @Published private(set) var barTucked = false

    @Published var collapseOnScroll: Bool {
        didSet { UserDefaults.standard.set(collapseOnScroll, forKey: "crowser.collapseOnScroll") }
    }
    @Published var suggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(suggestionsEnabled, forKey: "crowser.suggestions") }
    }
    @Published var blockTrackers: Bool {
        didSet {
            UserDefaults.standard.set(blockTrackers, forKey: ContentBlocker.storageKey)
            tabs.forEach { $0.refreshContentRules() }
        }
    }
    @Published var hideCookieBanners: Bool {
        didSet {
            UserDefaults.standard.set(hideCookieBanners, forKey: ContentBlocker.cookieKey)
            tabs.forEach { $0.refreshContentRules() }
        }
    }

    let library: Library
    let sites = SiteSettings()
    private(set) var contentRules: WKContentRuleList?
    private(set) var cookieRules: WKContentRuleList?
    private(set) var liteRules: WKContentRuleList?
    /// Private tabs stay covered until Face ID (or the passcode) unlocks them.
    @Published private(set) var privateUnlocked = false
    /// Toolbar and status bar both hidden.
    @Published private(set) var fullscreen = false

    private let tabsKey = "crowser.tabs"
    private let selectedKey = "crowser.selectedTab"
    private var toastTask: Task<Void, Never>?
    /// Pages from recently closed (non-private) tabs, newest last.
    @Published private(set) var closedPages: [URL] = []
    var canReopenClosedTab: Bool { !closedPages.isEmpty }

    init(library: Library) {
        self.library = library
        let defaults = UserDefaults.standard
        collapseOnScroll = defaults.object(forKey: "crowser.collapseOnScroll") as? Bool ?? true
        suggestionsEnabled = defaults.object(forKey: "crowser.suggestions") as? Bool ?? true
        blockTrackers = ContentBlocker.isEnabled
        hideCookieBanners = defaults.bool(forKey: ContentBlocker.cookieKey)

        if defaults.bool(forKey: "crowserSeed") { library.seedDemo() }
        if !defaults.bool(forKey: "crowserFresh") { restore() }
        // Screenshot hook: "-crowserOpen 'https://a|https://b'" opens those pages in fresh tabs.
        for link in (defaults.string(forKey: "crowserOpen") ?? "").split(separator: "|") {
            if let url = URL(string: String(link)) { newTab(url: url, focus: false) }
        }
        if tabs.isEmpty { newTab(focus: false) }

        Task { await loadContentRules() }
        Task { await runDemoHooks() }
        ControllerBridge.shared.store = self
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.sleepBackgroundTabs()
            }
        }
    }

    private var sleepTask: Task<Void, Never>?

    // MARK: Sleeping tabs and quiet gaming

    /// Unloads tabs you haven't looked at for a while (or all background tabs when memory runs low).
    /// They keep their history, scroll position and preview, and wake when you open them.
    func sleepBackgroundTabs(force: Bool = false) {
        let minutes = Prefs.shared.sleepAfter
        guard force || minutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(max(minutes, 1)) * 60)
        for tab in tabs where tab.id != selectedID && !tab.pinned && !tab.sleeping && (force || tab.lastActive < cutoff) {
            tab.sleep()
        }
    }

    /// While a game is on screen, pauses sound and video in every other tab.
    func quietOthers(for tab: BrowserTab) {
        guard Prefs.shared.quietWhileGaming, tab.id == selectedID else { return }
        for other in tabs where other.id != tab.id {
            other.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    var current: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    // MARK: Tabs

    func newTab(url: URL? = nil, isPrivate: Bool = false, focus: Bool = true) {
        var url = url
        var focus = focus
        if url == nil {
            switch Prefs.shared.home {
            case .site:
                if let home = Prefs.shared.homePage {
                    url = home
                    focus = false
                }
            case .blank:
                url = URL(string: "about:blank")
            case .start:
                break
            }
        }
        let tab = BrowserTab(url: url, isPrivate: isPrivate, store: self)
        if !isPrivate { tab.groupID = activeGroupID }
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
        if let previous = current { Task { await previous.captureSnapshot(fresh: false) } }
        selectedID = tab.id
        tab.lastActive = Date()
        if tab.gameMode { quietOthers(for: tab) }
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
        tab.teardown()
        if !tab.isPrivate, let page = tab.pageURL {
            closedPages.append(page)
            if closedPages.count > 20 { closedPages.removeFirst() }
        }
        tabs.remove(at: index)
        if !tab.isPrivate && tab.url != nil {
            showToast("Tab closed", action: (title: "Undo", run: { [weak self] in self?.reopenClosedTab() }))
        }
        if tabs.isEmpty {
            newTab(focus: false)
        } else if selectedID == tab.id {
            selectedID = tabs[max(0, index - 1)].id
        }
        persist()
    }

    func runToastAction() {
        let action = toastAction
        toastAction = nil
        withAnimation(Motion.soft) { toast = nil }
        action?.run()
    }

    func reopenClosedTab() {
        guard let page = closedPages.popLast() else { return }
        newTab(url: page, focus: false)
        Haptics.tap()
    }

    /// Reopens one particular recently closed page.
    func reopen(_ page: URL) {
        if let index = closedPages.lastIndex(of: page) { closedPages.remove(at: index) }
        newTab(url: page, focus: false)
        Haptics.tap()
    }

    func closeCurrent() {
        if let current { close(current) }
    }

    func closeAll(isPrivate: Bool) {
        let doomed = tabs.filter { $0.isPrivate == isPrivate && !$0.pinned }
        doomed.forEach { $0.teardown() }
        let ids = Set(doomed.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        if tabs.isEmpty { newTab(focus: false) } else if current == nil || !tabs.contains(where: { $0.id == selectedID }) {
            selectedID = tabs.last?.id
        }
        persist()
    }

    /// Closes every other tab of the same kind (pinned tabs stay).
    func closeOthers(than keep: BrowserTab) {
        let doomed = tabs.filter { $0.id != keep.id && $0.isPrivate == keep.isPrivate && !$0.pinned }
        doomed.forEach { $0.teardown() }
        let ids = Set(doomed.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        selectedID = keep.id
        Haptics.thud()
        showToast("Closed \(doomed.count) tab\(doomed.count == 1 ? "" : "s")")
        persist()
    }

    func duplicate(_ tab: BrowserTab) {
        guard let page = tab.pageURL else { return }
        let copy = BrowserTab(url: page, isPrivate: tab.isPrivate, store: self)
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.insert(copy, at: index + 1)
        } else {
            tabs.append(copy)
        }
        selectedID = copy.id
        Haptics.tap()
        persist()
    }

    /// Pinned tabs sit first, survive "Close all" and auto-close.
    func togglePin(_ tab: BrowserTab) {
        tab.pinned.toggle()
        let pinned = tabs.filter(\.pinned)
        let rest = tabs.filter { !$0.pinned }
        tabs = pinned + rest
        Haptics.select()
        showToast(tab.pinned ? "Pinned" : "Unpinned")
        persist()
    }

    /// Pushes changed global settings into every open tab.
    func prefsChanged() {
        tabs.forEach { $0.reapplyPrefs() }
    }

    /// Opens the overview straight away; the current tab's preview fills in a moment later.
    func showOverview() {
        endEditing()
        let tab = current
        Task { await tab?.captureSnapshot(fresh: false) }
        withAnimation(Motion.soft) { showingOverview = true }
    }

    // MARK: Groups

    @discardableResult
    func createGroup(named name: String, with tab: BrowserTab? = nil) -> TabGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = TabGroup(name: trimmed.isEmpty ? "Group \(groups.count + 1)" : trimmed, tone: groups.count % 6)
        groups.append(group)
        tab?.groupID = group.id
        activeGroupID = group.id
        Haptics.success()
        persist()
        return group
    }

    func move(_ tab: BrowserTab, to group: TabGroup?) {
        tab.groupID = group?.id
        objectWillChange.send()
        Haptics.select()
        showToast(group.map { "Moved to \($0.name)" } ?? "Removed from group")
        persist()
    }

    func renameGroup(_ group: TabGroup, to name: String) {
        guard let index = groups.firstIndex(of: group) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        groups[index].name = trimmed
        persist()
    }

    func recolorGroup(_ group: TabGroup) {
        guard let index = groups.firstIndex(of: group) else { return }
        groups[index].tone = (groups[index].tone + 1) % 6
        Haptics.select()
        persist()
    }

    /// Removes the group; its tabs stay open, ungrouped.
    func ungroup(_ group: TabGroup) {
        tabs.filter { $0.groupID == group.id }.forEach { $0.groupID = nil }
        groups.removeAll { $0.id == group.id }
        if activeGroupID == group.id { activeGroupID = nil }
        persist()
    }

    func closeGroup(_ group: TabGroup) {
        let doomed = tabs.filter { $0.groupID == group.id }
        doomed.forEach { $0.teardown() }
        let ids = Set(doomed.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        groups.removeAll { $0.id == group.id }
        if activeGroupID == group.id { activeGroupID = nil }
        if tabs.isEmpty { newTab(focus: false) } else if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs.last?.id }
        Haptics.thud()
        persist()
    }

    func group(for tab: BrowserTab) -> TabGroup? {
        guard let id = tab.groupID else { return nil }
        return groups.first { $0.id == id }
    }

    // MARK: Sessions

    /// Saves the open tabs (only the shown group's, when one is picked) under a name.
    func saveSession(named name: String) {
        let source = tabs.filter { !$0.isPrivate && (activeGroupID == nil || $0.groupID == activeGroupID) }
        let links = source.compactMap { $0.pageURL?.absoluteString }
        guard !links.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        sessions.insert(SavedSession(name: trimmed.isEmpty ? fallback : trimmed, links: links), at: 0)
        saveWorkspace()
        Haptics.success()
        showToast("Saved \(links.count) tab\(links.count == 1 ? "" : "s")")
    }

    /// Reopens a session as its own group. Tabs load when you look at them.
    func openSession(_ session: SavedSession) {
        let group = TabGroup(name: session.name, tone: groups.count % 6)
        groups.append(group)
        var first: BrowserTab?
        for link in session.links {
            let tab = BrowserTab(url: URL(string: link), lazy: true, store: self)
            tab.groupID = group.id
            tabs.append(tab)
            if first == nil { first = tab }
        }
        activeGroupID = group.id
        if let first { selectedID = first.id }
        Haptics.success()
        persist()
    }

    func deleteSession(_ session: SavedSession) {
        sessions.removeAll { $0.id == session.id }
        saveWorkspace()
    }

    private func saveWorkspace() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(groups) { defaults.set(data, forKey: "crowser.groups") }
        if let data = try? JSONEncoder().encode(sessions) { defaults.set(data, forKey: "crowser.sessions") }
    }

    private func loadWorkspace() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "crowser.groups"), let saved = try? JSONDecoder().decode([TabGroup].self, from: data) {
            groups = saved
        }
        if let data = defaults.data(forKey: "crowser.sessions"), let saved = try? JSONDecoder().decode([SavedSession].self, from: data) {
            sessions = saved
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

    // MARK: Private lock

    var privateLocked: Bool { Prefs.shared.lockPrivate && !privateUnlocked }

    func unlockPrivate() async {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            privateUnlocked = true
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your private tabs")) ?? false
        if ok {
            withAnimation(Motion.soft) { privateUnlocked = true }
            Haptics.success()
        }
    }

    /// Turning the lock on shouldn't lock you out of the tab you're in; it starts next time.
    func keepPrivateUnlockedForNow() {
        privateUnlocked = true
    }

    /// Called when Crowser goes to the background.
    func lockPrivate() {
        privateUnlocked = false
    }

    // MARK: Fullscreen

    func enterFullscreen() {
        Haptics.thud()
        withAnimation(Motion.snappy) {
            fullscreen = true
            barTucked = true
        }
    }

    /// Folds the bar into its small pill right now.
    func collapseBar() {
        guard let tab = current else { return }
        if tab.showsStartPage || UIDevice.current.userInterfaceIdiom == .pad {
            tuckBar()
            return
        }
        Haptics.tap()
        withAnimation(Motion.snappy) { tab.setCollapsed(true) }
    }

    /// Hides the bar completely; only the pull tab stays.
    func tuckBar() {
        Haptics.thud()
        withAnimation(Motion.snappy) { barTucked = true }
        current?.setCollapsed(false)
    }

    func untuckBar() {
        Haptics.tap()
        withAnimation(Motion.snappy) {
            barTucked = false
            fullscreen = false
        }
        current?.setCollapsed(false)
    }

    func toggleTuck() {
        barTucked ? untuckBar() : tuckBar()
    }

    func showToast(_ message: String, action: (title: String, run: () -> Void)? = nil) {
        toastTask?.cancel()
        toastAction = action
        withAnimation(Motion.snappy) { toast = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: action == nil ? 1_800_000_000 : 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.soft) { toast = nil }
        }
    }

    // MARK: Content blocking

    private func loadContentRules() async {
        contentRules = await ContentBlocker.compile()
        cookieRules = await ContentBlocker.compileCookieRules()
        liteRules = await ContentBlocker.compileLite()
        tabs.forEach { $0.refreshContentRules() }
    }

    // MARK: Persistence

    /// Saves the non-private tabs so they come back next launch.
    func persist() {
        let saved = tabs.filter { !$0.isPrivate }
        let links = saved.map { $0.pageURL?.absoluteString ?? "" }
        let selected = saved.firstIndex { $0.id == selectedID } ?? max(0, saved.count - 1)
        UserDefaults.standard.set(links, forKey: tabsKey)
        UserDefaults.standard.set(saved.map(\.pinned), forKey: tabsKey + ".pinned")
        UserDefaults.standard.set(saved.map { $0.lastActive.timeIntervalSince1970 }, forKey: tabsKey + ".active")
        UserDefaults.standard.set(selected, forKey: selectedKey)
        UserDefaults.standard.set(saved.map { $0.groupID?.uuidString ?? "" }, forKey: tabsKey + ".group")
        saveWorkspace()
    }

    /// Back/forward history for every tab, kept on disk so restored tabs can still go back.
    func persistHistory() {
        let saved = tabs.filter { !$0.isPrivate }
        var states: [String: Data] = [:]
        for tab in saved {
            if let link = tab.pageURL?.absoluteString, let state = tab.stateData { states[link] = state }
        }
        if let data = try? PropertyListEncoder().encode(states) {
            try? data.write(to: Self.historyFile, options: .atomic)
        }
    }

    private static var historyFile: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tab-history.plist")
    }

    private func restore() {
        let defaults = UserDefaults.standard
        let links = defaults.stringArray(forKey: tabsKey) ?? []
        let pins = defaults.array(forKey: tabsKey + ".pinned") as? [Bool] ?? []
        let active = defaults.array(forKey: tabsKey + ".active") as? [Double] ?? []
        let groupIDs = defaults.stringArray(forKey: tabsKey + ".group") ?? []
        loadWorkspace()
        let known = Set(groups.map(\.id))
        let selected = defaults.integer(forKey: selectedKey)
        let days = Prefs.shared.autoCloseDays
        let states = (try? Data(contentsOf: Self.historyFile))
            .flatMap { try? PropertyListDecoder().decode([String: Data].self, from: $0) } ?? [:]
        var selectedTab: BrowserTab?
        for (index, link) in links.enumerated() {
            let pinned = pins.indices.contains(index) && pins[index]
            let last = active.indices.contains(index) ? Date(timeIntervalSince1970: active[index]) : Date()
            // Auto-close: tabs nobody looked at for too long quietly go to "recently closed".
            if days > 0, !pinned, index != selected, Date().timeIntervalSince(last) > Double(days) * 86_400 {
                if let url = URL(string: link) { closedPages.append(url) }
                continue
            }
            let tab = BrowserTab(url: URL(string: link), lazy: true, store: self)
            tab.pinned = pinned
            tab.lastActive = last
            if let state = states[link] { tab.restoreState(state) }
            if groupIDs.indices.contains(index), let id = UUID(uuidString: groupIDs[index]), known.contains(id) {
                tab.groupID = id
            }
            tabs.append(tab)
            if index == selected { selectedTab = tab }
        }
        selectedID = selectedTab?.id ?? tabs.last?.id
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
        case "tucked":
            tuckBar()
        case "palette":
            sheet = .palette
        case "qrcode":
            sheet = .qrCode
        case "pad":
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let tab = current {
                if !tab.gameMode { tab.toggleGameMode() }
                if !tab.padOn { tab.togglePad() }
            }
        case "groups":
            if let first = tabs.first { createGroup(named: "Games", with: first) }
            if tabs.count > 1 { createGroup(named: "Reading", with: tabs[1]) }
            activeGroupID = nil
            for tab in tabs {
                selectedID = tab.id
                try? await Task.sleep(nanoseconds: 700_000_000)
                await tab.captureSnapshot()
            }
            showOverview()
        case "shields":
            sheet = .shields
        case "morefull":
            sheet = .more
        default:
            break
        }
    }
}
