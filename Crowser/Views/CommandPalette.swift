import SwiftUI

/// One box for everything: type to find any action, open tab, favorite or address. ⌘K on a keyboard.
struct CommandPalette: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Command: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var detail: String? = nil
        var keywords: String = ""
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.ember)
                TextField("Type a command, tab or address", text: $query)
                    .font(Face.ui(17, weight: .medium))
                    .foregroundColor(Theme.text)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { if let first = results.first { perform(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).stroke(Theme.ember.opacity(focused ? 0.8 : 0), lineWidth: 1.5))
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        Button { perform(command) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(index == 0 && !query.isEmpty ? Theme.onEmber : Theme.text)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.r(9), style: .continuous)
                                            .fill(index == 0 && !query.isEmpty ? Theme.ember : Theme.line)
                                    )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(command.title)
                                        .font(Face.ui(15, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    if let detail = command.detail {
                                        Text(detail)
                                            .font(Face.ui(12))
                                            .foregroundColor(Theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .modifier(SheetChrome())
        .onAppear { focused = true }
    }

    private var results: [Command] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = commands + tabCommands + favoriteCommands
        guard !needle.isEmpty else { return commands }
        var found = all.filter { matches($0, needle) }
        if let url = Address.resolve(query) {
            let isSearch = Address.shortcut(in: query) != nil || SearchEngine.allCases.contains { $0.url(for: query) == url }
            found.append(Command(
                id: "go",
                title: isSearch ? "Search for “\(query)”" : "Open \(Address.display(url))",
                symbol: isSearch ? "magnifyingglass" : "arrow.up.right",
                run: { store.open(url) }
            ))
        }
        return found
    }

    /// Every word typed must appear somewhere in the title, detail or keywords.
    private func matches(_ command: Command, _ needle: String) -> Bool {
        let haystack = (command.title + " " + (command.detail ?? "") + " " + command.keywords).lowercased()
        return needle.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    private func perform(_ command: Command) {
        Haptics.tap()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { command.run() }
    }

    private var tab: BrowserTab? { store.current }

    private var commands: [Command] {
        var list: [Command] = [
            Command(id: "new", title: "New Tab", symbol: "plus.square", keywords: "open", run: { store.newTab() }),
            Command(id: "private", title: "New Private Tab", symbol: "eye.slash", keywords: "incognito", run: { store.newTab(isPrivate: true) }),
            Command(id: "tabs", title: "Show Tabs", symbol: "square.on.square", keywords: "overview groups", run: { store.showOverview() }),
            Command(id: "group", title: "New Tab Group", symbol: "rectangle.stack.badge.plus", keywords: "group", run: {
                Task {
                    if let name = await Presenter.prompt(title: "New group", message: "Name it, like Games or School", defaultText: nil) {
                        store.createGroup(named: name, with: store.current?.isPrivate == false ? store.current : nil)
                    }
                }
            }),
            Command(id: "session", title: "Save Tabs as Session", symbol: "square.and.arrow.down.on.square", keywords: "session save", run: {
                Task {
                    if let name = await Presenter.prompt(title: "Save tabs", message: "Name this session", defaultText: nil) {
                        store.saveSession(named: name)
                    }
                }
            }),
            Command(id: "reopen", title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", keywords: "undo restore", run: { store.reopenClosedTab() }),
            Command(id: "library", title: "Favorites & History", symbol: "books.vertical", keywords: "bookmarks library", run: { store.sheet = .library }),
            Command(id: "settings", title: "Settings", symbol: "gearshape", keywords: "preferences options", run: { store.sheet = .settings }),
            Command(id: "shields", title: "Shields", symbol: "checkmark.shield", keywords: "privacy trackers block", run: { store.sheet = .shields }),
            Command(id: "hidebar", title: store.barTucked ? "Show Toolbar" : "Hide Toolbar", symbol: "rectangle.bottomhalf.inset.filled", keywords: "bar tuck", run: { store.toggleTuck() }),
            Command(id: "scan", title: "Scan QR Code", symbol: "qrcode.viewfinder", keywords: "camera qr barcode", run: { store.sheet = .qrScan }),
            Command(id: "fullscreen", title: "Fullscreen", symbol: "arrow.up.left.and.arrow.down.right", keywords: "full screen hide bar immersive", run: { store.enterFullscreen() }),
            Command(id: "lite", title: prefs.liteMode ? "Turn Off Lite Mode" : "Lite Mode", symbol: "hare", keywords: "data slow images fast", run: {
                prefs.liteMode.toggle()
                store.prefsChanged()
                store.current?.webView.reload()
            }),
            Command(id: "backup", title: "Back Up Everything", symbol: "externaldrive.badge.plus", keywords: "export settings save", run: {
                if let file = Backup.export() { Presenter.share([file]) }
            }),
            Command(id: "sleep", title: "Sleep Other Tabs", symbol: "moon.zzz", keywords: "memory free unload", run: {
                store.sleepBackgroundTabs(force: true)
                store.showToast("Other tabs are asleep")
            }),
            Command(id: "cookies", title: "Manage Cookies", symbol: "list.bullet.rectangle", keywords: "cookies privacy", run: { store.sheet = .settings }),
            Command(id: "theme", title: "Switch Light / Dark", symbol: "circle.lefthalf.filled", keywords: "theme appearance dark mode", run: {
                prefs.appearance = prefs.appearance == .dark ? .light : .dark
            }),
        ]
        for session in store.sessions {
            list.append(Command(id: "s-\(session.id)", title: "Open Session: \(session.name)", symbol: "tray.full", detail: "\(session.links.count) tabs", keywords: "session", run: { store.openSession(session) }))
        }
        for group in store.groups {
            list.append(Command(id: "g-\(group.id)", title: "Show Group: \(group.name)", symbol: "rectangle.stack", keywords: "group", run: {
                store.activeGroupID = group.id
                store.showOverview()
            }))
        }
        guard let tab, tab.url != nil, !tab.showsStartPage else { return list }
        let page: [Command] = [
            Command(id: "reader", title: tab.readerOn ? "Exit Reader" : "Reader View", symbol: "doc.plaintext", keywords: "article read", run: { tab.toggleReader() }),
            Command(id: "find", title: "Find on Page", symbol: "text.magnifyingglass", keywords: "search", run: { tab.findOnPage() }),
            Command(id: "translate", title: "Translate Page", symbol: "character.bubble", keywords: "language", run: { tab.translate() }),
            Command(id: "define", title: "Look Up Word", symbol: "character.book.closed", keywords: "dictionary define meaning", run: { tab.define() }),
            Command(id: "pip", title: "Picture in Picture", symbol: "pip.enter", keywords: "video float pip", run: { tab.pictureInPicture() }),
            Command(id: "aloud", title: "Read Aloud", symbol: "speaker.wave.2", keywords: "speak voice", run: { tab.readAloud() }),
            Command(id: "shot", title: "Full-Page Screenshot", symbol: "camera.viewfinder", keywords: "capture image whole", run: { tab.fullPageScreenshot() }),
            Command(id: "qr", title: "Show QR Code for Page", symbol: "qrcode", keywords: "share qr", run: { store.sheet = .qrCode }),
            Command(id: "media", title: "Save Video or Audio", symbol: "arrow.down.circle", keywords: "download media mp4 music", run: { tab.saveMedia() }),
            Command(id: "watch", title: tab.watching ? "Stop Watching Page" : "Watch Page for Changes", symbol: "eye", keywords: "monitor alert change refresh", run: { tab.toggleWatch() }),
            Command(id: "note", title: "Notes for This Site", symbol: "note.text", keywords: "memo write", run: { store.sheet = .note }),
            Command(id: "awake", title: tab.keepAwake ? "Let Screen Sleep Here" : "Keep Screen On Here", symbol: "sun.max", keywords: "awake dim lock", run: { tab.toggleKeepAwake() }),
            Command(id: "pdf", title: "Save as PDF", symbol: "doc.richtext", keywords: "export print", run: { tab.saveAsPDF() }),
            Command(id: "source", title: "View Page Source", symbol: "chevron.left.forwardslash.chevron.right", keywords: "html code", run: { tab.viewSource() }),
            Command(id: "hide", title: "Hide an Item on the Page", symbol: "eye.slash.circle", keywords: "zap remove element", run: { tab.toggleZapper() }),
            Command(id: "game", title: tab.gameMode ? "Turn Off Game Mode" : "Game Mode", symbol: "gamecontroller", keywords: "play", run: { tab.toggleGameMode() }),
            Command(id: "fps", title: tab.showsFPS ? "Hide FPS Counter" : "Show FPS Counter", symbol: "speedometer", keywords: "frames game performance", run: {
                if !tab.gameMode { tab.toggleGameMode() }
                tab.toggleFPS()
            }),
            Command(id: "pad", title: tab.padOn ? "Hide On-Screen Controls" : "On-Screen Controls", symbol: "dpad", keywords: "joystick gamepad buttons touch game", run: {
                if !tab.gameMode { tab.toggleGameMode() }
                tab.togglePad()
            }),
            Command(id: "rotate", title: tab.orientation == nil ? "Lock Rotation Here" : "Unlock Rotation Here", symbol: "lock.rotation", keywords: "orientation landscape portrait", run: {
                if tab.orientation == nil {
                    let landscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
                    tab.setOrientation(landscape ? "landscape" : "portrait")
                } else {
                    tab.setOrientation(nil)
                }
            }),
            Command(id: "dark", title: tab.darkPage ? "Light Page" : "Dark Page", symbol: "moon", keywords: "night invert", run: { tab.toggleDarkPage() }),
            Command(id: "desktop", title: tab.isDesktop ? "Mobile Site" : "Desktop Site", symbol: "desktopcomputer", keywords: "request", run: { tab.toggleDesktop() }),
            Command(id: "agent", title: tab.agentID == nil ? "Identify as Chrome" : "Identify as Crowser", symbol: "theatermasks", keywords: "user agent browser pretend", run: { tab.setAgent(tab.agentID == nil ? "chrome-win" : nil) }),
            Command(id: "shieldsdown", title: tab.shieldsDown ? "Shields Up Here" : "Shields Down Here", symbol: "shield.slash", keywords: "privacy block site", run: { tab.toggleShields() }),
            Command(id: "pin", title: tab.pinned ? "Unpin Tab" : "Pin Tab", symbol: "pin", run: { store.togglePin(tab) }),
            Command(id: "dup", title: "Duplicate Tab", symbol: "plus.square.on.square", run: { store.duplicate(tab) }),
            Command(id: "others", title: "Close Other Tabs", symbol: "xmark.square", run: { store.closeOthers(than: tab) }),
            Command(id: "close", title: "Close Tab", symbol: "xmark", run: { store.close(tab) }),
            Command(id: "fav", title: library.isBookmarked(tab.url) ? "Remove from Favorites" : "Add to Favorites", symbol: "star", keywords: "bookmark", run: { store.toggleBookmarkForCurrent() }),
            Command(id: "copy", title: "Copy Link", symbol: "link", keywords: "url", run: {
                if let url = tab.url { UIPasteboard.general.url = Address.cleaned(url) ?? url }
                store.showToast("Link copied")
            }),
            Command(id: "hard", title: "Reload Without Cache", symbol: "arrow.clockwise.circle", keywords: "refresh hard", run: { tab.hardReload() }),
            Command(id: "top", title: "Scroll to Top", symbol: "arrow.up.to.line", run: { tab.scrollToTop() }),
            Command(id: "bottom", title: "Scroll to Bottom", symbol: "arrow.down.to.line", run: { tab.scrollToBottom() }),
            Command(id: "code", title: "Custom CSS & JavaScript", symbol: "paintbrush.pointed", keywords: "style script userscript", run: { store.sheet = .siteCode }),
            Command(id: "clear", title: "Clear This Site's Data", symbol: "trash", keywords: "cookies storage", run: { Task { await tab.clearSiteData() } }),
        ]
        return page + list
    }

    private var tabCommands: [Command] {
        store.tabs.filter { $0.id != store.selectedID }.map { other in
            Command(
                id: "t-\(other.id)",
                title: other.showsStartPage ? "New tab" : (other.title.isEmpty ? Address.display(other.url) : other.title),
                symbol: "square.on.square",
                detail: "Switch to tab · \(Address.display(other.url))",
                keywords: other.url?.absoluteString ?? "",
                run: { store.select(other) }
            )
        }
    }

    private var favoriteCommands: [Command] {
        library.bookmarks.map { entry in
            Command(id: "b-\(entry.id)", title: entry.title, symbol: "star", detail: Address.display(entry.url), keywords: entry.url.absoluteString, run: { store.open(entry.url) })
        }
    }
}
