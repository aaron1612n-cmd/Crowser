import SwiftUI
import WebKit

struct SettingsSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var sites: SiteSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SearchEngine.storageKey) private var engine: SearchEngine = .duckDuckGo
    @State private var clearedData = false
    @State private var confirmClear = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                lookSection
                accessibilitySection

                Section {
                    Picker(selection: $engine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                    } label: {
                        row("Search engine", symbol: "magnifyingglass")
                    }
                    if engine == .custom {
                        TextField("https://example.com/search?q=%s", text: $prefs.customEngine)
                            .font(Face.mono(14))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle(isOn: $store.suggestionsEnabled) {
                        row("Search suggestions", symbol: "text.bubble")
                    }
                    NavigationLink {
                        ShortcutsEditor()
                    } label: {
                        row("Search shortcuts", symbol: "command", detail: "\(prefs.shortcuts.count)")
                    }
                } header: {
                    header("Search")
                } footer: {
                    Text(engine == .custom ? "Put %s where the search words go." : "Type a shortcut and a space, like “yt lofi” or “w crows”, to search that site directly.")
                }

                Section {
                    Picker(selection: $prefs.home) {
                        ForEach(HomeChoice.allCases) { Text($0.name).tag($0) }
                    } label: {
                        row("New tabs open", symbol: "house")
                    }
                    if prefs.home == .site {
                        TextField("example.com", text: $prefs.homeURL)
                            .font(Face.mono(14))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle(isOn: $prefs.showFavorites) {
                        row("Favorites on start page", symbol: "star")
                    }
                    Toggle(isOn: $prefs.showRecent) {
                        row("Recent pages on start page", symbol: "clock")
                    }
                    Toggle(isOn: $prefs.linksInBackground) {
                        row("Open links in background", symbol: "square.stack")
                    }
                    Toggle(isOn: $prefs.swipeTabs) {
                        row("Swipe the bar to switch tabs", symbol: "hand.draw")
                    }
                    Toggle(isOn: $store.collapseOnScroll) {
                        row("Shrink bar while scrolling", symbol: "arrow.down.right.and.arrow.up.left")
                    }
                    Picker(selection: $prefs.autoCloseDays) {
                        Text("Never").tag(0)
                        Text("After a day").tag(1)
                        Text("After a week").tag(7)
                        Text("After a month").tag(30)
                    } label: {
                        row("Close unused tabs", symbol: "timer")
                    }
                } header: {
                    header("Browsing")
                } footer: {
                    Text("Unused tabs close the next time you open Crowser and wait under Reopen. Pinned tabs never close on their own.")
                }

                Section {
                    Toggle(isOn: $store.blockTrackers) { row("Ads & trackers", symbol: "hand.raised") }
                    Toggle(isOn: $store.hideCookieBanners) { row("Cookie popups", symbol: "checkmark.seal") }
                    Toggle(isOn: $prefs.httpsOnly) { row("HTTPS only", symbol: "lock") }
                    Toggle(isOn: $prefs.fingerprinting) { row("Fingerprint blocking", symbol: "touchid") }
                    Toggle(isOn: $prefs.cleanLinks) { row("Clean links", symbol: "link") }
                    Toggle(isOn: $prefs.stripReferrer) { row("Hide where you came from", symbol: "arrow.uturn.left") }
                    Toggle(isOn: $prefs.blockPopups) { row("Block popups", symbol: "macwindow") }
                    Toggle(isOn: $prefs.blockAutoplay) { row("Block autoplay", symbol: "play.slash") }
                    Toggle(isOn: $prefs.fraudWarnings) { row("Fraud warnings", symbol: "exclamationmark.triangle") }
                    Toggle(isOn: $prefs.javaScript) { row("JavaScript", symbol: "curlybraces") }
                    Toggle(isOn: $prefs.darkPages) { row("Dark pages everywhere", symbol: "moon") }
                } header: {
                    header("Shields")
                } footer: {
                    Text("Each switch is the default for every site. Tap the shield in the address bar to drop them all on one site.")
                }

                Section {
                    NavigationLink {
                        SitesList()
                    } label: {
                        row("Site settings", symbol: "globe", detail: "\(sites.allSites.count)")
                    }
                } footer: {
                    Text("Game mode, shields, text size, desktop version and custom code you've set for each site.")
                }

                Section {
                    Button {
                        confirmClear = true
                    } label: {
                        row("Clear history", symbol: "clock.arrow.circlepath", detail: "\(library.history.count) pages")
                    }
                    Button {
                        WKWebsiteDataStore.default().removeData(
                            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                            modifiedSince: .distantPast
                        ) {
                            clearedData = true
                            Haptics.success()
                        }
                    } label: {
                        row("Clear cookies & site data", symbol: "trash", detail: clearedData ? "Cleared" : nil)
                    }
                } header: {
                    header("Privacy")
                }

                Section {
                    HStack {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text("Crowser").font(Face.title(20, weight: .bold))
                            Circle().fill(Theme.ember).frame(width: 6, height: 6).padding(.leading, 2)
                        }
                        Spacer()
                        Text(version)
                            .font(Face.ui(14, weight: .medium))
                            .foregroundColor(Theme.muted)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .tint(Theme.ember)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Face.ui(16, weight: .bold))
                }
            }
            .onChange(of: prefs.fingerprinting) { _ in store.prefsChanged() }
            .onChange(of: prefs.stripReferrer) { _ in store.prefsChanged() }
            .onChange(of: prefs.blockPopups) { _ in store.prefsChanged() }
            .onChange(of: prefs.javaScript) { _ in store.prefsChanged() }
            .onChange(of: prefs.darkPages) { _ in store.prefsChanged() }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    library.clearHistory()
                    Haptics.success()
                }
            }
        }
        .modifier(SheetChrome())
    }

    // MARK: Look

    private var lookSection: some View {
        Section {
            Picker(selection: $prefs.appearance) {
                ForEach(Appearance.allCases) { Text($0.name).tag($0) }
            } label: {
                row("Theme", symbol: "circle.lefthalf.filled")
            }
            VStack(alignment: .leading, spacing: 10) {
                row("Accent", symbol: "paintpalette", detail: prefs.accent.name)
                HStack(spacing: 0) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            Haptics.select()
                            prefs.accent = choice
                        } label: {
                            Circle()
                                .fill(Color(uiColor: .hex(choice.hex)))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Theme.text, lineWidth: prefs.accent == choice ? 2.5 : 0).padding(-4))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                        .accessibilityAddTraits(prefs.accent == choice ? .isSelected : [])
                    }
                }
            }
            Picker(selection: $prefs.barStyle) {
                ForEach(BarStyle.allCases) { Text($0.name).tag($0) }
            } label: {
                row("Bar style", symbol: "rectangle.bottomthird.inset.filled")
            }
            Picker(selection: $prefs.barPosition) {
                ForEach(BarPosition.allCases) { Text($0.name).tag($0) }
            } label: {
                row("Bar position", symbol: "arrow.up.and.down")
            }
            Toggle(isOn: $prefs.compact) {
                row("Compact bar", symbol: "rectangle.compress.vertical")
            }
            VStack(alignment: .leading, spacing: 6) {
                row("Corners", symbol: "square.on.circle", detail: prefs.roundness < 0.15 ? "Sharp" : (prefs.roundness > 1.2 ? "Round" : "\(Int(prefs.roundness * 100))%"))
                Slider(value: $prefs.roundness, in: 0...1.4, step: 0.1)
            }
        } header: {
            header("Look")
        }
    }

    private var accessibilitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                row("Interface text size", symbol: "textformat.size", detail: "\(Int((prefs.textScale * 100).rounded()))%")
                Slider(value: $prefs.textScale, in: 0.85...1.35, step: 0.05)
            }
            Toggle(isOn: $prefs.boldText) { row("Bold text", symbol: "bold") }
            Toggle(isOn: $prefs.highContrast) { row("High contrast", symbol: "circle.righthalf.filled") }
            Toggle(isOn: $prefs.reduceMotion) { row("Reduce motion", symbol: "figure.walk") }
            Toggle(isOn: $prefs.haptics) { row("Haptics", symbol: "waveform") }
            Button {
                prefs.resetLook()
                Haptics.success()
            } label: {
                row("Reset look", symbol: "arrow.counterclockwise")
            }
        } header: {
            header("Accessibility")
        } footer: {
            Text("Page text size is set per site from the … menu.")
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Face.ui(13, weight: .bold))
            .foregroundColor(Theme.muted)
            .textCase(nil)
    }

    private func row(_ title: String, symbol: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.onInk)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.r(8), style: .continuous).fill(Theme.bar))
            Text(title)
                .font(Face.ui(16, weight: .medium))
                .foregroundColor(Theme.text)
            if let detail {
                Spacer()
                Text(detail)
                    .font(Face.ui(14))
                    .foregroundColor(Theme.muted)
            }
        }
    }
}

/// Edit, add and remove search shortcuts.
private struct ShortcutsEditor: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var keyword = ""
    @State private var name = ""
    @State private var template = ""

    var body: some View {
        Form {
            Section {
                ForEach(prefs.shortcuts) { shortcut in
                    HStack(spacing: 12) {
                        Text(shortcut.keyword)
                            .font(Face.ui(15, weight: .heavy))
                            .foregroundColor(Theme.ember)
                            .frame(minWidth: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.name).font(Face.ui(15, weight: .semibold))
                            Text(shortcut.template).font(Face.mono(11)).foregroundColor(Theme.muted).lineLimit(1)
                        }
                    }
                }
                .onDelete { prefs.shortcuts.remove(atOffsets: $0) }
                .onMove { prefs.shortcuts.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Swipe to delete. Type the keyword, a space, then your search.")
            }

            Section {
                TextField("Keyword (like yt)", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Name (like YouTube)", text: $name)
                TextField("https://site.com/search?q=%s", text: $template)
                    .font(Face.mono(14))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add shortcut") {
                    let word = keyword.trimmingCharacters(in: .whitespaces).lowercased()
                    prefs.shortcuts.removeAll { $0.keyword == word }
                    prefs.shortcuts.append(SearchShortcut(keyword: word, name: name.isEmpty ? word : name, template: template))
                    keyword = ""
                    name = ""
                    template = ""
                    Haptics.success()
                }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || !template.contains("%s"))
                Button("Restore defaults") {
                    prefs.shortcuts = SearchShortcut.defaults
                }
            } header: {
                Text("New shortcut")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Search shortcuts")
        .toolbar { EditButton() }
    }
}

/// Every site with remembered settings.
private struct SitesList: View {
    @EnvironmentObject private var sites: SiteSettings
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        Form {
            if sites.allSites.isEmpty {
                Text("Nothing yet. Settings you change from the … menu on a site show up here.")
                    .font(Face.ui(14))
                    .foregroundColor(Theme.muted)
            } else {
                Section {
                    ForEach(sites.allSites, id: \.self) { host in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(host).font(Face.ui(16, weight: .semibold))
                            Text(tags(for: host))
                                .font(Face.ui(12))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .onDelete { offsets in
                        let hosts = sites.allSites
                        offsets.map { hosts[$0] }.forEach { sites.remove($0) }
                        store.prefsChanged()
                    }
                } footer: {
                    Text("Swipe a site to forget everything set for it.")
                }
                Section {
                    Button("Forget all site settings", role: .destructive) {
                        sites.clearAll()
                        store.prefsChanged()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Site settings")
    }

    private func tags(for host: String) -> String {
        guard let site = sites.sites[host] else { return "" }
        var tags: [String] = []
        if site.shieldsDown { tags.append("Shields down") }
        if site.game { tags.append("Game mode") }
        if site.allowTrackers { tags.append("Trackers allowed") }
        if site.javaScript == false { tags.append("JavaScript off") }
        if site.javaScript == true { tags.append("JavaScript on") }
        if site.darkPage == true { tags.append("Dark") }
        if site.darkPage == false { tags.append("Never dark") }
        if site.desktop == true { tags.append("Desktop") }
        if site.desktop == false { tags.append("Mobile") }
        if let zoom = site.zoom { tags.append("Text \(Int(zoom * 100))%") }
        if !site.css.isEmpty { tags.append("Custom CSS") }
        if !site.js.isEmpty { tags.append("Custom JS") }
        return tags.isEmpty ? "Default" : tags.joined(separator: " · ")
    }
}
