import SwiftUI
import UIKit
import WebKit

// MARK: - Start page wallpaper

enum Wallpaper {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("wallpaper.jpg")
    }

    @MainActor private static var cached: UIImage?
    @MainActor private static var cachedVersion = -1

    /// The picture, scaled down so it never costs much memory.
    @MainActor static func image(version: Int) -> UIImage? {
        guard version > 0 else { return nil }
        if cachedVersion == version { return cached }
        cached = UIImage(contentsOfFile: file.path)
        cachedVersion = version
        return cached
    }

    /// Saves a picked photo as a phone-sized JPEG.
    static func save(_ data: Data) -> Bool {
        guard let source = UIImage(data: data) else { return false }
        let longest: CGFloat = 1800
        let scale = min(1, longest / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return false }
        return (try? jpeg.write(to: file, options: .atomic)) != nil
    }

    static func remove() {
        try? FileManager.default.removeItem(at: file)
    }
}

// MARK: - App icon

enum AppIconChoice: String, CaseIterable, Identifiable {
    case shield, paper, moss, signal, bone, ember
    var id: String { rawValue }

    var name: String {
        switch self {
        case .shield: return "Shield"
        case .paper: return "Paper"
        case .moss: return "Moss"
        case .signal: return "Signal"
        case .bone: return "Bone"
        case .ember: return "Ember"
        }
    }

    /// The alternate icon's asset name (nil = the main icon).
    var assetName: String? { self == .shield ? nil : "AppIcon-" + name }

    /// Swatch colors: background, shield.
    var swatch: (bg: UInt32, mark: UInt32) {
        switch self {
        case .shield: return (0x171614, 0xE2531F)
        case .paper: return (0xF4F0E8, 0xE2531F)
        case .moss: return (0x171614, 0x6F9A45)
        case .signal: return (0x171614, 0xE8C21A)
        case .bone: return (0x171614, 0xF4F0E8)
        case .ember: return (0xE2531F, 0x171614)
        }
    }

    @MainActor static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.assetName == name } ?? .shield
    }

    @MainActor func apply() {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(assetName) { _ in }
    }
}

// MARK: - Settings backup

/// Everything Crowser remembers (settings, favorites, history, site settings, groups, sessions) in one file.
enum Backup {
    private static func isOurs(_ key: String) -> Bool {
        key.hasPrefix("crowser.") && !key.hasPrefix("crowser.tabs") && key != "crowser.selectedTab"
    }

    static func export() -> URL? {
        let all = UserDefaults.standard.dictionaryRepresentation().filter { isOurs($0.key) }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: all, format: .binary, options: 0) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Crowser backup \(stamp).crowserbackup")
        return (try? data.write(to: file, options: .atomic)) != nil ? file : nil
    }

    /// Returns how many settings were restored, or nil when the file isn't a Crowser backup.
    static func restore(from url: URL) -> Int? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let all = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let ours = all.filter { isOurs($0.key) }
        guard !ours.isEmpty else { return nil }
        for (key, value) in ours { UserDefaults.standard.set(value, forKey: key) }
        return ours.count
    }
}

// MARK: - Save video or audio from a page

extension PageScripts {
    /// The address of the playing (or first) video or audio on the page.
    static let mediaSource = """
    (function(){
      var list=[].slice.call(document.querySelectorAll('video,audio'));
      if(!list.length)return 'none';
      list.sort(function(a,b){return (b.paused?0:1)-(a.paused?0:1);});
      for(var i=0;i<list.length;i++){
        var m=list[i];var src=m.currentSrc||m.src;
        if(!src){var s=m.querySelector('source');if(s)src=s.src;}
        if(src)return src;
      }
      return 'none';
    })();
    """
}

extension BrowserTab {
    func saveMedia() {
        webView.evaluateJavaScript(PageScripts.mediaSource) { [weak self] result, _ in
            Task { @MainActor in
                guard let tab = self else { return }
                let source = (result as? String) ?? "none"
                guard source != "none", let url = URL(string: source) else {
                    tab.store?.showToast("No video or audio on this page")
                    return
                }
                guard url.scheme?.hasPrefix("http") == true, !url.path.lowercased().hasSuffix(".m3u8") else {
                    tab.store?.showToast("This one streams in pieces and can't be saved")
                    return
                }
                await tab.download(url)
            }
        }
    }

    private func download(_ url: URL) async {
        store?.showToast("Saving \(url.lastPathComponent.isEmpty ? "media" : url.lastPathComponent)…")
        var request = URLRequest(url: url)
        if let page = self.url { request.setValue(page.absoluteString, forHTTPHeaderField: "Referer") }
        if let agent = webView.customUserAgent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let header = HTTPCookie.requestHeaderFields(with: cookies.filter { url.host?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) == true })
        for (key, value) in header { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (temp, response) = try await URLSession.shared.download(for: request)
            let name = response.suggestedFilename ?? (url.lastPathComponent.isEmpty ? "media.mp4" : url.lastPathComponent)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temp, to: file)
            Haptics.success()
            Presenter.share([file])
        } catch {
            store?.showToast("Couldn't save it")
        }
    }
}
