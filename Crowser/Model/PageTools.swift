import AVFoundation
import SwiftUI
import WebKit

/// Page tools: reader view, PDF, source, translate, read aloud, hide-element, site info.
extension BrowserTab {
    // MARK: Reader

    func toggleReader() {
        guard url != nil else { return }
        if readerOn {
            setReader(false)
            webView.reload()
            return
        }
        let hex = String(format: "#%06X", Look.accent.hex)
        webView.evaluateJavaScript(PageScripts.reader(accent: hex)) { [weak self] result, _ in
            guard let tab = self else { return }
            Task { @MainActor in
                if (result as? String) == "none" {
                    tab.store?.showToast("No article found on this page")
                } else {
                    tab.setReader(true)
                    Haptics.success()
                }
            }
        }
    }

    // MARK: Translate

    func translate() {
        guard let page = webView.url ?? url, page.scheme?.hasPrefix("http") == true else { return }
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        var components = URLComponents(string: "https://translate.google.com/translate")
        components?.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: language),
            URLQueryItem(name: "u", value: page.absoluteString),
        ]
        if let target = components?.url { load(target) }
    }

    // MARK: PDF

    func saveAsPDF() {
        guard url != nil else { return }
        store?.showToast("Making PDF…")
        let name = (title.isEmpty ? Address.display(url) : title)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            Task { @MainActor in
                guard case .success(let data) = result else { return }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(String(name.prefix(80)) + ".pdf")
                try? data.write(to: file)
                Haptics.success()
                Presenter.share([file])
            }
        }
    }

    // MARK: Full-page screenshot

    /// The whole page, top to bottom, as one tall image.
    func fullPageScreenshot() {
        guard url != nil else { return }
        store?.showToast("Capturing the whole page…")
        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            Task { @MainActor in
                guard case .success(let data) = result,
                      let provider = CGDataProvider(data: data as CFData),
                      let pdf = CGPDFDocument(provider), pdf.numberOfPages > 0 else {
                    self?.store?.showToast("Couldn't capture this page")
                    return
                }
                var pages: [CGPDFPage] = []
                for index in 1...pdf.numberOfPages { if let page = pdf.page(at: index) { pages.append(page) } }
                let width = pages.map { $0.getBoxRect(.mediaBox).width }.max() ?? 1
                let height = pages.reduce(CGFloat(0)) { $0 + $1.getBoxRect(.mediaBox).height }
                // Keep very long pages under the size iOS will happily share.
                let scale = min(2, 16_000 / max(height, 1))
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
                let image = renderer.image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    var y: CGFloat = 0
                    for page in pages {
                        let box = page.getBoxRect(.mediaBox)
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: 0, y: y + box.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.drawPDFPage(page)
                        cg.restoreGState()
                        y += box.height
                    }
                }
                Haptics.success()
                Presenter.share([image])
            }
        }
    }

    // MARK: Source

    func viewSource() {
        guard url != nil else { return }
        let host = Address.display(url)
        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
            Task { @MainActor in
                let html = (result as? String) ?? ""
                let controller = UIHostingController(rootView: SourceView(title: host, text: html))
                Presenter.present(controller)
            }
        }
    }

    // MARK: Read aloud

    func readAloud() {
        if Speaker.shared.isSpeaking {
            Speaker.shared.stop()
            return
        }
        webView.evaluateJavaScript(PageScripts.readableText) { result, _ in
            Task { @MainActor in
                let text = (result as? String) ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Speaker.shared.speak(text)
            }
        }
    }

    // MARK: Picture in picture

    func pictureInPicture() {
        webView.evaluateJavaScript(PageScripts.pictureInPicture) { [weak self] result, _ in
            Task { @MainActor in
                switch result as? String {
                case "ok": Haptics.tap()
                case "none": self?.store?.showToast("No video on this page")
                default: self?.store?.showToast("Start the video, then try again")
                }
            }
        }
    }

    // MARK: Dictionary

    /// Looks up the selected word, or asks for one when nothing is selected.
    func define() {
        webView.evaluateJavaScript(PageScripts.selectedText) { result, _ in
            Task { @MainActor in
                var term = (result as? String) ?? ""
                if term.isEmpty {
                    term = await Presenter.prompt(title: "Look up", message: "Select a word on the page, or type one", defaultText: nil) ?? ""
                }
                term = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { return }
                Presenter.present(UIReferenceLibraryViewController(term: term))
            }
        }
    }

    // MARK: FPS counter

    var showsFPS: Bool { store?.sites.setting(for: url).fps ?? false }

    func toggleFPS() {
        let on = !showsFPS
        store?.sites.update(url) { $0.fps = on }
        rebuildUserScripts()
        if on {
            webView.evaluateJavaScript(PageScripts.fps, completionHandler: nil)
        } else {
            webView.evaluateJavaScript("window.__crowserFPS=false;var f=document.getElementById('crowser-fps');if(f)f.remove();", completionHandler: nil)
        }
        objectWillChange.send()
        Haptics.select()
    }

    // MARK: Hide elements

    func toggleZapper() {
        guard url != nil else { return }
        if zapping {
            setZapping(false)
            webView.evaluateJavaScript("window.__crowserZap && location.reload();", completionHandler: nil)
            return
        }
        setZapping(true)
        webView.evaluateJavaScript(PageScripts.zapper, completionHandler: nil)
        store?.showToast("Tap something to hide it")
    }

    /// The page reported a hidden element: remember it for this site.
    func didZap(_ selector: String) {
        setZapping(false)
        let rule = "/*hidden*/ \(selector) { display: none !important; }"
        store?.sites.update(url) { site in
            site.css = site.css.isEmpty ? rule : site.css + "\n" + rule
        }
        rebuildUserScripts()
        Haptics.thud()
        store?.showToast("Hidden. Undo in this site's settings")
    }

    var hiddenCount: Int {
        (store?.sites.setting(for: url).css ?? "").components(separatedBy: "/*hidden*/").count - 1
    }

    func restoreHidden() {
        store?.sites.update(url) { site in
            site.css = site.css
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("/*hidden*/") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        rebuildUserScripts()
        webView.reload()
        Haptics.select()
    }

    // MARK: Site data

    func cookieCount() async -> Int {
        guard let key = SiteSettings.key(for: url) else { return 0 }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return cookies.filter { $0.domain.hasSuffix(key) || key.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }.count
    }

    /// Forgets cookies, storage and cache for this site only, then reloads it.
    func clearSiteData() async {
        guard let key = SiteSettings.key(for: url) else { return }
        let dataStore = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let matching = records.filter { $0.displayName.hasSuffix(key) || key.hasSuffix($0.displayName) }
        await dataStore.removeData(ofTypes: types, for: matching)
        Haptics.success()
        store?.showToast("Cleared \(Address.display(url))")
        webView.reload()
    }
}

/// Lets the page talk back (hide-element results) without the content controller keeping the tab alive.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    init(_ tab: BrowserTab) {
        self.tab = tab
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let selector = message.body as? String else { return }
        let tab = self.tab
        Task { @MainActor in tab?.didZap(selector) }
    }
}

/// Read aloud, with the system's voices.
@MainActor
final class Speaker: NSObject, ObservableObject {
    static let shared = Speaker()

    @Published private(set) var isSpeaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in Speaker.shared.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in Speaker.shared.isSpeaking = false }
    }
}

/// Page source, selectable and searchable with the system find bar.
struct SourceView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceTextView(text: text)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = text
                            Haptics.success()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Copy source")
                    }
                }
        }
        .tint(Theme.ember)
    }
}

private struct SourceTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isFindInteractionEnabled = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.backgroundColor = Theme.paperUI
        view.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 40, right: 10)
        view.text = String(text.prefix(400_000))
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}
}
