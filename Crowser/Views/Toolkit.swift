import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit
import WebKit

// MARK: - QR scanner

/// Point the camera at a QR code; a link opens in a new tab, anything else is copied.
struct QRScannerSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView { payload in
                        Haptics.success()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if let url = URL(string: payload), url.scheme?.hasPrefix("http") == true {
                                store.newTab(url: url, focus: false)
                            } else if let url = Address.resolve(payload), !payload.contains(" ") {
                                store.newTab(url: url, focus: false)
                            } else {
                                UIPasteboard.general.string = payload
                                store.showToast("Copied what the code says")
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 40, weight: .semibold)).foregroundColor(Theme.muted)
                        Text("This iPhone's camera can't scan here, or camera access is off in Settings.")
                            .font(Face.ui(15))
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.paper)
                }
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .dataMatrix])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    found(payload)
                    return
                }
            }
        }
    }
}

// MARK: - QR code for the page

struct QRCodeSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    private var link: URL? { store.current?.url.map { Address.cleaned($0) ?? $0 } }

    var body: some View {
        VStack(spacing: 18) {
            Text("Scan to open")
                .font(Face.title(24, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(.top, 26)
            if let link, let image = Self.code(for: link.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: Theme.r(22), style: .continuous).fill(Color.white))
                Text(Address.display(link))
                    .font(Face.ui(14, weight: .semibold))
                    .foregroundColor(Theme.muted)
                Button {
                    Presenter.share([image])
                } label: {
                    Label("Share code", systemImage: "square.and.arrow.up")
                        .font(Face.ui(16, weight: .bold))
                        .foregroundColor(Theme.onEmber)
                        .frame(maxWidth: 260, minHeight: 50)
                        .background(Capsule().fill(Theme.ember))
                }
                .buttonStyle(PressStyle())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(SheetChrome())
    }

    static func code(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Notes for a site

struct SiteNoteSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(Face.ui(17))
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.paper.ignoresSafeArea())
                .navigationTitle("Notes · \(Address.display(store.current?.url))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            store.current?.saveNote(text)
                            Haptics.success()
                            dismiss()
                        }
                        .font(Face.ui(16, weight: .bold))
                    }
                }
                .onAppear {
                    text = store.current?.note ?? ""
                    focused = true
                }
        }
        .modifier(SheetChrome())
    }
}

// MARK: - Cookie manager

/// Every site that has stored cookies, with how many. Swipe to delete a site's cookies.
struct CookieManager: View {
    @State private var cookies: [HTTPCookie] = []
    @State private var search = ""
    @State private var loaded = false

    private struct Site: Identifiable {
        let domain: String
        let count: Int
        var id: String { domain }
    }

    private var sites: [Site] {
        let grouped = Dictionary(grouping: cookies) { cookie -> String in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        }
        let needle = search.lowercased()
        return grouped
            .map { Site(domain: $0.key, count: $0.value.count) }
            .filter { needle.isEmpty || $0.domain.contains(needle) }
            .sorted { $0.count == $1.count ? $0.domain < $1.domain : $0.count > $1.count }
    }

    var body: some View {
        List {
            if loaded && sites.isEmpty {
                Text(search.isEmpty ? "No cookies stored." : "No matches.")
                    .font(Face.ui(15))
                    .foregroundColor(Theme.muted)
            }
            Section {
                ForEach(sites) { site in
                    HStack {
                        Text(site.domain).font(Face.ui(15, weight: .semibold))
                        Spacer()
                        Text("\(site.count)")
                            .font(Face.ui(14, weight: .semibold))
                            .foregroundColor(Theme.muted)
                            .monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { sites[$0].domain }
                    Task { await delete(domains: doomed) }
                }
            } footer: {
                if !cookies.isEmpty {
                    Text("\(cookies.count) cookies from \(sites.count) sites. Swipe a site to delete its cookies.")
                }
            }
            if !cookies.isEmpty {
                Section {
                    Button("Delete every cookie", role: .destructive) {
                        Task { await delete(domains: sites.map(\.domain)) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .searchable(text: $search, prompt: "Find a site")
        .navigationTitle("Cookies")
        .task { await reload() }
    }

    private func reload() async {
        cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        loaded = true
    }

    private func delete(domains: [String]) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies where domains.contains(where: { cookie.domain.hasSuffix($0) }) {
            await store.deleteCookie(cookie)
        }
        Haptics.success()
        await reload()
    }
}

// MARK: - Private tab lock

/// Covers private tabs until Face ID or the passcode unlocks them.
struct PrivateLockView: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(Theme.ember)
            Text("Private tabs are locked")
                .font(Face.title(24, weight: .bold))
                .foregroundColor(Theme.onInk)
            Button {
                Task { await store.unlockPrivate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(Face.ui(17, weight: .bold))
                    .foregroundColor(Theme.onEmber)
                    .frame(width: 200, height: 52)
                    .background(Capsule().fill(Theme.ember))
            }
            .buttonStyle(PressStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink.ignoresSafeArea())
        .task { await store.unlockPrivate() }
    }
}
