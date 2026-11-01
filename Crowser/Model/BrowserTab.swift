import UIKit
import WebKit

/// One tab: owns its WKWebView and mirrors the bits of its state the chrome needs.
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let isPrivate: Bool
    let webView: WKWebView

    @Published private(set) var title = ""
    @Published private(set) var url: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    /// Called when a page finishes loading (never for private tabs).
    var onVisit: ((String, URL) -> Void)?
    /// Called when a page asks for a new window (target=_blank, window.open).
    var onOpenInNewTab: ((URL) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    static let safariUserAgentSuffix: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1"
    }()

    init(url: URL? = nil, isPrivate: Bool = false) {
        self.isPrivate = isPrivate

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended
        // Present as Safari. A bare WKWebView user agent has no "Version/… Safari/…" token, and some sites
        // and image CDNs then pick formats or markup meant for other browsers, leaving broken-image boxes.
        configuration.applicationNameForUserAgent = BrowserTab.safariUserAgentSuffix

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observe()
        if let url { load(url) }
    }

    // MARK: Actions

    func load(_ url: URL) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
        self.url = url
    }

    func reload() {
        guard url != nil else { return }
        webView.reload()
    }

    func stop() { webView.stopLoading() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    @objc private func pulledToRefresh(_ control: UIRefreshControl) {
        webView.reload()
        control.endRefreshing()
    }

    // MARK: State mirroring

    private func observe() {
        let handler: (WKWebView, Any) -> Void = { [weak self] _, _ in
            guard let tab = self else { return }
            Task { @MainActor in tab.sync() }
        }
        observations = [
            webView.observe(\.title) { view, change in handler(view, change) },
            webView.observe(\.url) { view, change in handler(view, change) },
            webView.observe(\.estimatedProgress) { view, change in handler(view, change) },
            webView.observe(\.isLoading) { view, change in handler(view, change) },
            webView.observe(\.canGoBack) { view, change in handler(view, change) },
            webView.observe(\.canGoForward) { view, change in handler(view, change) },
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
    }
}

extension BrowserTab: WKNavigationDelegate {
    private static let inAppSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        if Self.inAppSchemes.contains(scheme) { return .allow }
        // mailto:, tel:, app links and the like go to the system.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        guard !isPrivate, let url = webView.url, url.scheme?.hasPrefix("http") == true else { return }
        onVisit?(webView.title ?? "", url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        sync()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        sync()
    }
}

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if let open = onOpenInNewTab {
                open(url)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}
