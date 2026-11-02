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

    var showsStartPage: Bool { url == nil && !openedByPage }

    static let zoomSteps: [CGFloat] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2]

    static let safariSuffix: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1"
    }()

    static let desktopAgent: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }()

    private var observations: [NSKeyValueObservation] = []
    private var scrollRun: CGFloat = 0
    private var downloads: [ObjectIdentifier: URL] = [:]
    /// Restored tabs wait to load until you actually look at them, so launch stays instant.
    private var needsLoad = false

    init(url: URL? = nil, isPrivate: Bool = false, lazy: Bool = false, configuration: WKWebViewConfiguration? = nil, store: BrowserStore? = nil) {
        self.isPrivate = isPrivate
        self.openedByPage = configuration != nil
        self.store = store
        let desktop = UIDevice.current.userInterfaceIdiom == .pad
        self.isDesktop = desktop

        let configuration = configuration ?? Self.makeConfiguration(isPrivate: isPrivate)
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

        observe()
        if let rules = store?.contentRules { webView.configuration.userContentController.add(rules) }
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
        guard needsLoad, let url else { return }
        needsLoad = false
        load(url)
    }

    private static func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
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
        isDesktop.toggle()
        webView.customUserAgent = isDesktop ? Self.desktopAgent : nil
        if url != nil { webView.reload() }
        Haptics.select()
    }

    func stepZoom(_ direction: Int) {
        let current = Self.zoomSteps.firstIndex { $0 >= zoom - 0.001 } ?? 3
        let next = min(max(current + direction, 0), Self.zoomSteps.count - 1)
        zoom = Self.zoomSteps[next]
        webView.pageZoom = zoom
        Haptics.select()
    }

    func resetZoom() {
        zoom = 1
        webView.pageZoom = 1
    }

    func findOnPage() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    func captureSnapshot() async {
        guard url != nil, webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = NSNumber(value: 420)
        if let image = try? await webView.takeSnapshot(configuration: configuration) {
            snapshot = image
        }
    }

    func setContentRules(_ rules: WKContentRuleList?, enabled: Bool) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if enabled, let rules { controller.add(rules) }
    }

    // MARK: Bar collapse while scrolling

    func setCollapsed(_ collapsed: Bool) {
        if barCollapsed != collapsed { barCollapsed = collapsed }
        scrollRun = 0
    }

    private func scrolled(from old: CGFloat, to new: CGFloat) {
        let scrollView = webView.scrollView
        guard store?.collapseOnScroll ?? true, scrollView.isTracking || scrollView.isDecelerating else { return }
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
            webView.scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                guard let tab = self, let old = change.oldValue?.y, let new = change.newValue?.y, old != new else { return }
                Task { @MainActor in tab.scrolled(from: old, to: new) }
            },
        ]
    }

    private func sync() {
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
        preferences.preferredContentMode = isDesktop ? .desktop : .mobile
        if navigationAction.shouldPerformDownload { return (.download, preferences) }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return (.allow, preferences)
        }
        if Self.inAppSchemes.contains(scheme) { return (.allow, preferences) }
        // mailto:, tel:, maps, app links: hand to the system.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return (.cancel, preferences)
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
        setCollapsed(false)
        sync()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
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
        let link = elementInfo.linkURL
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            guard let link, let tab = self else { return UIMenu(children: suggested) }
            let ours = UIMenu(options: .displayInline, children: [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                    tab.store?.openInBackground(link, isPrivate: tab.isPrivate)
                },
                UIAction(title: "Open in Private Tab", image: UIImage(systemName: "eye.slash")) { _ in
                    tab.store?.newTab(url: link, isPrivate: true, focus: false)
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = link
                    tab.store?.showToast("Link copied")
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
