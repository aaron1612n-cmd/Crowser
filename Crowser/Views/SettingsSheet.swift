import SwiftUI
import WebKit

struct SettingsSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
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
                Section {
                    Picker(selection: $engine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                    } label: {
                        row("Search engine", symbol: "magnifyingglass")
                    }
                    Toggle(isOn: $store.suggestionsEnabled) {
                        row("Search suggestions", symbol: "text.bubble")
                    }
                } header: {
                    header("Search")
                } footer: {
                    Text("Suggestions come from DuckDuckGo as you type. Never sent from private tabs.")
                }

                Section {
                    Toggle(isOn: $store.blockTrackers) {
                        row("Block ads & trackers", symbol: "hand.raised")
                    }
                    Toggle(isOn: $store.hideCookieBanners) {
                        row("Hide cookie popups", symbol: "checkmark.shield")
                    }
                    Toggle(isOn: $store.collapseOnScroll) {
                        row("Shrink bar while scrolling", symbol: "arrow.down.right.and.arrow.up.left")
                    }
                } header: {
                    header("Browsing")
                } footer: {
                    Text("Blocks known ad and tracking networks only, so sites keep working. Hiding cookie popups skips consent banners on many sites.")
                }

                if !store.sites.gameSites.isEmpty {
                    Section {
                        ForEach(store.sites.gameSites, id: \.self) { host in
                            row(host, symbol: "gamecontroller.fill")
                        }
                    } header: {
                        header("Game mode sites")
                    } footer: {
                        Text("Turn game mode off from the … menu while on the site.")
                    }
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
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    library.clearHistory()
                    Haptics.success()
                }
            }
        }
        .modifier(SheetChrome())
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.bar))
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
