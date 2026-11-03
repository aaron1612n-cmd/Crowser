import UIKit
import WebKit

/// One tab: owns its WKWebView and mirrors the bits of its state the interface needs.
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    struct LoadError: Equatable {
        let url: URL?
        let message: String
        let offline: Bool
    }

    let id = UUID()
    let isPrivate: Bool
    /// Opened by a page (window.open / target=_blank) rather than by the user.
    let openedByPage: Bool
    let webView: WKWebView
    weak var store: BrowserStore?

    @Published private(set) var title = ""
    @Published private(set) var url: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isSecure = false
    @Published private(set) var loadError: LoadError?
    @Published private(set) var barCollapsed = false
    @Published private(set) var isDesktop: Bool
    @Published private(set) var zoom: CGFloat = 1
    @Published var snapshot: UIImage?
    /// Game mode: nothing on the page reacts to long-presses, selection, zoom or edge swipes.
    @Published private(set) var gameMode = false
    @Published private(set) var scrollLocked = false
    /// Ad/tracker blocking switched off for this site.
    @Published private(set) var trackersAllowed = false
    /// In game mode the bar is hidden until you tap the corner button.
    @Published var gameBarShown = false
    /// Every protection off for this site.
    @Published private(set) var shieldsDown = false
    @Published private(set) var javaScriptOn = true
    @Published private(set) var darkPage = false
    @Published private(set) var readerOn = false
    @Published private(set) var zapping = false
    /// Seconds between automatic reloads, 0 for off.
    @Published private(set) var autoRefresh = 0
    @Published var pinned = false
    @Published var groupID: UUID?
    /// Site-chosen browser identity (nil = Safari).
    @Published private(set) var agentID: String?
    @Published private(set) var keepAwake = false
    /// Rotation lock for this site: "portrait", "landscape" or nil to follow the phone.
    @Published var orientation: String?
    /// On-screen stick and buttons (game mode).
    @Published var padOn = false
    /// Asleep: the page is unloaded to save memory, but its back/forward history is kept.
    @Published private(set) var sleeping = false
    /// Saved back/forward history and scroll position (WKWebView.interactionState).
    private var savedState: Any?
    /// Watching the page: it reloads on the auto-refresh timer and you hear about it when the text changes.
    @Published private(set) var watching = false
    private var watchHash: Int?
    /// Keys currently held by the on-screen pad or a controller.
    var heldKeys: Set<GameKey> = []
    @Published var lastActive = Date()
    /// One load with blocking switched off ("Reload without blocking").
    private var bypassBlocking = false
    private var autoRefreshTask: Task<Void, Never>?
    /// The http address an https upgrade came from, so a failed upgrade can fall back.
    private var upgradedFrom: URL?
    /// Hosts that failed over https this session; HTTPS-only leaves them alone.
    static var httpOnlyHosts: Set<String> = []

    var showsStartPage: Bool { url == nil && !openedByPage }

    static let zoomSteps: [CGFloat] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2]

    static let safariSuffix: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1"
    }()

    /// Browsers a site can be told it's talking to.
    static let agents: [(id: String, name: String, desktop: Bool, string: String)] = [
        ("chrome-win", "Chrome on Windows", true,
         "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"),
        ("firefox-win", "Firefox on Windows", true,
         "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0"),
        ("chrome-android", "Chrome on Android", false,
         "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"),
        ("chrome-ios", "Chrome on iPhone", false,
         "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.0.0 Mobile/15E148 Safari/604.1"),
    ]

    static let desktopAgent: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }()

    private var observations: [NSKeyValueObservation] = []
    private var scrollRun: CGFloat = 0
    /// Height of the floating bar covering the bottom of the page (phones).
    private var bottomObstruction: CGFloat = 0
    private var downloads: [ObjectIdentifier: URL] = [:]
    /// Restored tabs wait to load until you actually look at them, so launch stays instant.
    private var needsLoad = false
    /// The site whose remembered settings are currently applied.
    private var siteKey: String?
    /// The address whose site settings are applied (may be ahead of `url` mid-navigation).
    private var siteURL: URL?

    init(url: URL? = nil, isPrivate: Bool = false, lazy: Bool = false, configuration: WKWebViewConfiguration? = nil, store: BrowserStore? = nil) {
        self.isPrivate = isPrivate
        self.openedByPage = configuration != nil
        self.store = store
        let desktop = UIDevice.current.userInterfaceIdiom == .pad
        self.isDesktop = desktop

        let configuration = configuration ?? Self.makeConfiguration(isPrivate: isPrivate)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !Prefs.shared.blockPopups
        configuration.applicationNameForUserAgent = Self.safariSuffix

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.backgroundColor = Theme.paperUI
        webView.scrollView.backgroundColor = Theme.paperUI
        webView.isFindInteractionEnabled = true
        webView.scrollView.alwaysBounceHorizontal = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        if desktop { webView.customUserAgent = Self.desktopAgent }
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        // Pages that fit the screen stay perfectly still: no bounce, no pull-down.
        webView.scrollView.alwaysBounceVertical = false

        // Pop-ups share their opener's content controller, which already has the handler.
        if !openedByPage {
            configuration.userContentController.add(WeakMessageHandler(self), name: "crowserZap")
        }

        observe()
        refreshContentRules()
        rebuildUserScripts()
        if let url {
            if lazy {
                self.url = url
                needsLoad = true
            } else {
                load(url)
            }
        }
    }

    /// Loads a restored tab the first time it comes on screen.
    func activate() {
        if sleeping || savedState != nil {
            wake()
            return
        }
        guard needsLoad, let url else { return }
        needsLoad = false
        load(url)
    }

    /// The page's address even while the tab is asleep.
    var pageURL: URL? { sleeping ? url : (webView.url ?? url) }

    /// History to hand back on the next launch, so restored tabs can still go back.
    var stateData: Data? {
        if sleeping || needsLoad { return savedState as? Data }
        return webView.interactionState as? Data
    }

    /// Restored tabs bring their back/forward history with them.
    func restoreState(_ data: Data) {
        savedState = data
    }

    /// Frees the page's memory. History, scroll position and the preview stay.
    func sleep() {
        guard !sleeping, !needsLoad, url != nil, !isPrivate, !watching, autoRefresh == 0 else { return }
        webView.requestMediaPlaybackState { [weak self] state in
            Task { @MainActor in
                guard let tab = self, state != .playing, !tab.sleeping else { return }
                tab.savedState = tab.webView.interactionState
                tab.sleeping = true
                tab.webView.stopLoading()
                tab.webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            }
        }
    }

    private func wake() {
        needsLoad = false
        let state = savedState
        savedState = nil
        sleeping = false
        if let state {
            webView.interactionState = state
        } else if let url {
            load(url)
        }
    }

    private static func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = Prefs.shared.blockAutoplay ? .all : .audio
        configuration.preferences.isFraudulentWebsiteWarningEnabled = Prefs.shared.fraudWarnings
        if #available(iOS 16.4, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        return configuration
    }

    // MARK: Navigation

    func load(_ url: URL) {
        loadError = nil
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
        self.url = url
        setCollapsed(false)
    }

    func reload() {
        if let error = loadError, let failed = error.url {
            load(failed)
        } else if url != nil {
            webView.reload()
        }
    }

    func stop() { webView.stopLoading() }

    /// Skips the cache: everything comes fresh from the server.
    func hardReload() {
        guard url != nil else { return }
        webView.reloadFromOrigin()
        Haptics.thud()
    }

    /// Reloads once with every blocker off, for when blocking breaks a page.
    func reloadWithoutBlocking() {
        guard url != nil else { return }
        bypassBlocking = true
        refreshContentRules()
        webView.reload()
        Haptics.thud()
    }

    func scrollToTop() {
        let scrollView = webView.scrollView
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top), animated: true)
    }

    func scrollToBottom() {
        let scrollView = webView.scrollView
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: max(bottom, -scrollView.adjustedContentInset.top)), animated: true)
    }

    func setAutoRefresh(_ seconds: Int) {
        autoRefresh = seconds
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        guard seconds > 0 else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard !Task.isCancelled, let tab = self else { return }
                if !tab.isLoading { tab.webView.reload() }
            }
        }
        Haptics.select()
    }

    func setReader(_ on: Bool) { readerOn = on }

    func toggleWatch() {
        watching.toggle()
        watchHash = nil
        if watching {
            if autoRefresh == 0 { setAutoRefresh(60) }
            checkForChanges()
            store?.showToast("Watching \(Address.display(url)) while Crowser is open")
        } else {
            setAutoRefresh(0)
        }
        Haptics.select()
    }

    /// Compares the page's visible text with last time.
    private func checkForChanges() {
        guard watching else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
            Task { @MainActor in
                guard let tab = self, tab.watching, let text = result as? String, !text.isEmpty else { return }
                let hash = text.hashValue
                if let old = tab.watchHash, old != hash {
                    Haptics.success()
                    tab.store?.showToast("\(Address.display(tab.url)) changed", action: (title: "Show", run: { [weak tab] in
                        guard let tab else { return }
                        tab.store?.hideOverview()
                        tab.store?.select(tab)
                    }))
                }
                tab.watchHash = hash
            }
        }
    }

    /// Tells this site Crowser is another browser (nil goes back to Safari).
    func setAgent(_ id: String?) {
        store?.sites.update(url) { $0.agent = id }
        let agent = id.flatMap { id in Self.agents.first { $0.id == id } }
        agentID = agent?.id
        isDesktop = agent?.desktop ?? (store?.sites.setting(for: url).desktop ?? (UIDevice.current.userInterfaceIdiom == .pad))
        webView.customUserAgent = agent?.string ?? (isDesktop ? Self.desktopAgent : nil)
        if url != nil { webView.reload() }
        Haptics.select()
    }

    func toggleKeepAwake() {
        keepAwake.toggle()
        let on = keepAwake
        store?.sites.update(url) { $0.awake = on }
        Haptics.select()
    }

    func saveNote(_ text: String) {
        store?.sites.update(url) { $0.note = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        objectWillChange.send()
    }

    var note: String { store?.sites.setting(for: url).note ?? "" }

    func setBottomObstruction(_ height: CGFloat) {
        guard bottomObstruction != height else { return }
        bottomObstruction = height
        updateBottomInset()
    }

    /// Pads the bottom so the last bit of a long page can scroll out from under the bar.
    /// Pages that already fit get no padding, so they can't be dragged.
    private func updateBottomInset() {
        let scrollView = webView.scrollView
        let safeBottom = scrollView.safeAreaInsets.bottom
        let visible = scrollView.bounds.height - scrollView.safeAreaInsets.top - safeBottom
        let needs = bottomObstruction > 0 && scrollView.contentSize.height > visible - bottomObstruction + 1
        let inset: CGFloat = needs ? bottomObstruction : 0
        if scrollView.contentInset.bottom != inset { scrollView.contentInset.bottom = inset }
        if scrollView.verticalScrollIndicatorInsets.bottom != bottomObstruction {
            scrollView.verticalScrollIndicatorInsets.bottom = bottomObstruction
        }
    }
    func setZapping(_ on: Bool) { zapping = on }

    /// Called when the tab closes.
    func teardown() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        stop()
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
        Haptics.tap()
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
        Haptics.tap()
    }

    func go(to item: WKBackForwardListItem) {
        webView.go(to: item)
    }

    // MARK: Page tools

    func toggleDesktop() {
        if agentID != nil {
            agentID = nil
            store?.sites.update(url) { $0.agent = nil }
        }
        isDesktop.toggle()
        webView.customUserAgent = isDesktop ? Self.desktopAgent : nil
        let desktop = isDesktop
        store?.sites.update(url) { $0.desktop = desktop }
        if url != nil { webView.reload() }
        Haptics.select()
    }

    func stepZoom(_ direction: Int) {
        let current = Self.zoomSteps.firstIndex { $0 >= zoom - 0.001 } ?? 3
        let next = min(max(current + direction, 0), Self.zoomSteps.count - 1)
        setZoom(Self.zoomSteps[next])
        Haptics.select()
    }

    func resetZoom() {
        setZoom(1)
    }

    private func setZoom(_ value: CGFloat) {
        zoom = value
        webView.pageZoom = value
        store?.sites.update(url) { $0.zoom = value == 1 ? nil : Double(value) }
    }

    // MARK: Per-site settings

    /// Applies what was remembered for the site a navigation is heading to.
    func applySiteSettings(for target: URL?) {
        guard let store else { return }
        siteKey = SiteSettings.key(for: target)
        siteURL = target
        let setting = store.sites.setting(for: target)

        let agent = setting.agent.flatMap { id in Self.agents.first { $0.id == id } }
        agentID = agent?.id
        keepAwake = setting.awake
        orientation = setting.orientation
        padOn = setting.pad
        let wantDesktop = agent?.desktop ?? setting.desktop ?? (UIDevice.current.userInterfaceIdiom == .pad)
        isDesktop = wantDesktop
        let wantAgent = agent?.string ?? (wantDesktop ? Self.desktopAgent : nil)
        if webView.customUserAgent != wantAgent { webView.customUserAgent = wantAgent }
        let prefs = Prefs.shared
        trackersAllowed = setting.allowTrackers
        shieldsDown = setting.shieldsDown
        javaScriptOn = setting.javaScript ?? prefs.javaScript
        darkPage = setting.darkPage ?? prefs.darkPages
        readerOn = false
        zapping = false
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(prefs.blockPopups && !setting.shieldsDown)
        refreshContentRules()
        zoom = CGFloat(setting.zoom ?? 1)
        setGame(setting.game, lock: setting.lockScroll, freshPage: true)
    }

    func refreshContentRules() {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard let store else { return }
        guard !shieldsDown && !bypassBlocking else { return }
        if store.blockTrackers && !trackersAllowed, let rules = store.contentRules { controller.add(rules) }
        if store.hideCookieBanners, let rules = store.cookieRules { controller.add(rules) }
        if Prefs.shared.liteMode, let rules = store.liteRules { controller.add(rules) }
    }

    func toggleTrackersAllowed() {
        trackersAllowed.toggle()
        let allowed = trackersAllowed
        store?.sites.update(url) { $0.allowTrackers = allowed }
        refreshContentRules()
        if url != nil { webView.reload() }
        Haptics.select()
    }

    // MARK: Shields and page styling

    /// Drops (or raises) every protection for this site.
    func toggleShields() {
        guard url != nil else { return }
        let down = !shieldsDown
        store?.sites.update(url) { $0.shieldsDown = down }
        shieldsDown = down
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(Prefs.shared.blockPopups && !down)
        refreshContentRules()
        rebuildUserScripts()
        webView.reload()
        Haptics.thud()
        store?.showToast(down ? "Shields down for \(Address.display(url))" : "Shields up")
    }

    func toggleJavaScript() {
        let on = !javaScriptOn
        javaScriptOn = on
        let global = Prefs.shared.javaScript
        store?.sites.update(url) { $0.javaScript = on == global ? nil : on }
        webView.reload()
        Haptics.select()
    }

    func toggleDarkPage() {
        let on = !darkPage
        darkPage = on
        let global = Prefs.shared.darkPages
        store?.sites.update(url) { $0.darkPage = on == global ? nil : on }
        rebuildUserScripts()
        if on {
            webView.evaluateJavaScript(PageScripts.darkPage, completionHandler: nil)
        } else {
            webView.evaluateJavaScript("var s=document.getElementById('crowser-dark'); if (s) s.remove();", completionHandler: nil)
        }
        Haptics.select()
    }

    /// Re-reads global defaults (after Settings changes) for the current site.
    func reapplyPrefs() {
        let setting = store?.sites.setting(for: url) ?? SiteSetting()
        javaScriptOn = setting.javaScript ?? Prefs.shared.javaScript
        darkPage = setting.darkPage ?? Prefs.shared.darkPages
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(Prefs.shared.blockPopups && !shieldsDown)
        refreshContentRules()
        rebuildUserScripts()
    }

    /// Saves your own CSS and JavaScript for this site and applies them now.
    func saveCustomization(css: String, js: String) {
        store?.sites.update(url) {
            $0.css = css
            $0.js = js
        }
        rebuildUserScripts()
        webView.reload()
    }

    /// Every script Crowser puts in pages, rebuilt from the current state.
    func rebuildUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let prefs = Prefs.shared
        let site = store?.sites.setting(for: siteURL ?? url) ?? SiteSetting()
        if !shieldsDown {
            if prefs.fingerprinting {
                controller.addUserScript(WKUserScript(source: PageScripts.fingerprint, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            }
            if prefs.stripReferrer {
                controller.addUserScript(WKUserScript(source: PageScripts.noReferrer, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        if darkPage {
            controller.addUserScript(WKUserScript(source: PageScripts.darkPage, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if gameMode {
            controller.addUserScript(WKUserScript(source: PageScripts.game, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
            controller.addUserScript(WKUserScript(source: PageScripts.keys, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            if site.fps {
                controller.addUserScript(WKUserScript(source: PageScripts.fps, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        if !site.css.isEmpty {
            controller.addUserScript(WKUserScript(source: PageScripts.userCSS(site.css), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if !site.js.isEmpty {
            controller.addUserScript(WKUserScript(source: PageScripts.userJS(site.js), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    // MARK: Game mode

    func toggleGameMode() {
        guard url != nil else { return }
        let on = !gameMode
        store?.sites.update(url) { $0.game = on }
        let lock = store?.sites.setting(for: url).lockScroll ?? true
        setGame(on, lock: lock, freshPage: false)
        // Styles added to the current page can't be taken back cleanly, so turning off reloads it.
        if !on { webView.reload() }
        Haptics.thud()
    }

    func toggleScrollLock() {
        let lock = !scrollLocked
        store?.sites.update(url) { $0.lockScroll = lock }
        setGame(gameMode, lock: lock, freshPage: false)
        Haptics.select()
    }

    private func setGame(_ on: Bool, lock: Bool, freshPage: Bool) {
        let turningOn = on && !gameMode
        gameMode = on
        scrollLocked = on && lock
        webView.allowsLinkPreview = !on
        webView.allowsBackForwardNavigationGestures = !on
        let scrollView = webView.scrollView
        scrollView.bounces = !on
        scrollView.pinchGestureRecognizer?.isEnabled = !on
        scrollView.isScrollEnabled = !(on && lock)

        rebuildUserScripts()
        if on {
            if turningOn && !freshPage {
                webView.evaluateJavaScript(PageScripts.game, completionHandler: nil)
                webView.evaluateJavaScript(PageScripts.keys, completionHandler: nil)
            }
            store?.quietOthers(for: self)
            setCollapsed(false)
        } else {
            gameBarShown = false
            releaseKeys()
        }
    }



    func findOnPage() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    /// `fresh` waits for the next screen update (sharper, but slower); tab switches skip it so they feel instant.
    func captureSnapshot(fresh: Bool = true) async {
        guard url != nil, webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = fresh
        configuration.snapshotWidth = NSNumber(value: 420)
        if let image = try? await webView.takeSnapshot(configuration: configuration) {
            snapshot = image
        }
    }

    // MARK: Bar collapse while scrolling

    func setCollapsed(_ collapsed: Bool) {
        if barCollapsed != collapsed { barCollapsed = collapsed }
        scrollRun = 0
    }

    private func scrolled(from old: CGFloat, to new: CGFloat) {
        let scrollView = webView.scrollView
        guard !(store?.barTucked ?? false), store?.collapseOnScroll ?? true, scrollView.isTracking || scrollView.isDecelerating else { return }
        let top = -scrollView.adjustedContentInset.top
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        if new <= top + 8 || new >= bottom - 8 {
            setCollapsed(false)
            return
        }
        let delta = new - old
        scrollRun = (delta > 0) == (scrollRun > 0) ? scrollRun + delta : delta
        if scrollRun > 36 && !barCollapsed {
            barCollapsed = true
        } else if scrollRun < -60 && barCollapsed {
            barCollapsed = false
        }
    }

    // MARK: State mirroring

    private func observe() {
        let refresh: (WKWebView, Any) -> Void = { [weak self] _, _ in
            guard let tab = self else { return }
            Task { @MainActor in tab.sync() }
        }
        observations = [
            webView.observe(\.title) { view, change in refresh(view, change) },
            webView.observe(\.url) { view, change in refresh(view, change) },
            webView.observe(\.estimatedProgress) { view, change in refresh(view, change) },
            webView.observe(\.isLoading) { view, change in refresh(view, change) },
            webView.observe(\.canGoBack) { view, change in refresh(view, change) },
            webView.observe(\.canGoForward) { view, change in refresh(view, change) },
            webView.observe(\.hasOnlySecureContent) { view, change in refresh(view, change) },
            webView.scrollView.observe(\.contentSize) { [weak self] _, _ in
                guard let tab = self else { return }
                Task { @MainActor in tab.updateBottomInset() }
            },
            // Bounds change on every scroll frame; only a size change matters here.
            webView.scrollView.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
                guard let tab = self, change.oldValue?.size != change.newValue?.size else { return }
                Task { @MainActor in tab.updateBottomInset() }
            },
            webView.scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                guard let tab = self, let old = change.oldValue?.y, let new = change.newValue?.y, old != new else { return }
                Task { @MainActor in tab.scrolled(from: old, to: new) }
            },
        ]
    }

    private func sync() {
        guard !sleeping else { return }
        let newTitle = webView.title ?? ""
        if title != newTitle { title = newTitle }
        if let newURL = webView.url, url != newURL { url = newURL }
        if progress != webView.estimatedProgress { progress = webView.estimatedProgress }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        let secure = webView.hasOnlySecureContent || webView.url?.scheme == "https"
        if isSecure != secure { isSecure = secure }
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {
    private static let inAppSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.targetFrame?.isMainFrame ?? true,
           let target = navigationAction.request.url,
           target.scheme?.hasPrefix("http") == true,
           SiteSettings.key(for: target) != siteKey {
            applySiteSettings(for: target)
        }
        preferences.preferredContentMode = isDesktop ? .desktop : .mobile
        preferences.allowsContentJavaScript = javaScriptOn
        if navigationAction.shouldPerformDownload { return (.download, preferences) }

        if navigationAction.targetFrame?.isMainFrame ?? true,
           let target = navigationAction.request.url,
           navigationAction.request.httpMethod?.uppercased() ?? "GET" == "GET",
           !shieldsDown {
            let prefs = Prefs.shared
            // Clean links: drop utm_*, fbclid, gclid and friends before the page ever sees them.
            if prefs.cleanLinks, target.scheme?.hasPrefix("http") == true, let clean = Address.cleaned(target) {
                load(clean)
                return (.cancel, preferences)
            }
            // HTTPS-only: try the secure version first; fall back if the site really has none.
            if prefs.httpsOnly, target.scheme?.lowercased() == "http", let host = target.host?.lowercased(),
               !Self.httpOnlyHosts.contains(host), !Self.isLocal(host),
               var components = URLComponents(url: target, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                if components.port == 80 { components.port = nil }
                if let secure = components.url {
                    upgradedFrom = target
                    load(secure)
                    return (.cancel, preferences)
                }
            }
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return (.allow, preferences)
        }
        if Self.inAppSchemes.contains(scheme) { return (.allow, preferences) }
        // mailto:, tel:, maps, app links: hand to the system.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return (.cancel, preferences)
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame else { return .allow }
        if !navigationResponse.canShowMIMEType { return .download }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        store?.showToast("Downloading…")
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        store?.showToast("Downloading…")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
        sync()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadError = nil
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        setCollapsed(false)
        sync()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        upgradedFrom = nil
        if bypassBlocking {
            bypassBlocking = false
            refreshContentRules()
        }
        checkForChanges()
        guard !isPrivate, let url = webView.url, url.scheme?.hasPrefix("http") == true else { return }
        store?.library.recordVisit(title: webView.title ?? "", url: url)
        store?.persist()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        sync()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        sync()
        let nsError = error as NSError
        // Cancelled loads and loads that turned into downloads aren't failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        // An HTTPS upgrade that failed: remember the host and go back to plain http.
        if let original = upgradedFrom, let host = original.host?.lowercased(),
           (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host?.lowercased() ?? host == host {
            upgradedFrom = nil
            Self.httpOnlyHosts.insert(host)
            load(original)
            store?.showToast("\(Address.display(original)) has no secure version")
            return
        }
        let failing = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        let offline = nsError.domain == NSURLErrorDomain
            && [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed].contains(nsError.code)
        loadError = LoadError(url: failing, message: nsError.localizedDescription, offline: offline)
        if let failing, url == nil { url = failing }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // Return a real web view so sign-in popups keep their link back to the page that opened them.
        return store?.openPopup(configuration: configuration, from: self)
    }

    func webViewDidClose(_ webView: WKWebView) {
        store?.close(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await Presenter.alert(title: frame.request.url?.host, message: message)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Presenter.confirm(title: frame.request.url?.host, message: message)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await Presenter.prompt(title: frame.request.url?.host, message: prompt, defaultText: defaultText)
    }

    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo
    ) async -> UIContextMenuConfiguration? {
        if gameMode { return nil }
        let link = elementInfo.linkURL
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            guard let link, let tab = self else { return UIMenu(children: suggested) }
            let ours = UIMenu(options: .displayInline, children: [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                    if Prefs.shared.linksInBackground {
                        tab.store?.openInBackground(link, isPrivate: tab.isPrivate)
                    } else {
                        tab.store?.newTab(url: link, isPrivate: tab.isPrivate, focus: false)
                    }
                },
                UIAction(title: "Open in Private Tab", image: UIImage(systemName: "eye.slash")) { _ in
                    tab.store?.newTab(url: link, isPrivate: true, focus: false)
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = Address.cleaned(link) ?? link
                    tab.store?.showToast("Link copied")
                },
                UIAction(title: "Share Link", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    Presenter.share([Address.cleaned(link) ?? link])
                },
            ])
            return UIMenu(children: [ours] + suggested)
        }
    }

    func webView(
        _ webView: WKWebView,
        contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let link = elementInfo.linkURL else { return }
        animator.addCompletion { [weak self] in self?.load(link) }
    }
}

// MARK: - Downloads

extension BrowserTab: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
        downloads[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Haptics.success()
        // The share sheet offers "Save to Files", Photos, AirDrop and other apps.
        Presenter.share([file])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        store?.showToast("Download failed")
    }
}
