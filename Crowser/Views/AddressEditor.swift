import SwiftUI

/// What the bar turns into when you tap the address: a search field with live suggestions,
/// favorites, and pages you've been to.
struct AddressEditor: View {
    @ObservedObject var tab: BrowserTab
    let barOnTop: Bool
    let morph: Namespace.ID

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @FocusState private var focused: Bool
    @State private var remote: [String] = []

    private var query: String { store.addressDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isBrowsingQuery: Bool { query.isEmpty || query == tab.url?.absoluteString }

    var body: some View {
        VStack(spacing: 0) {
            if barOnTop {
                field
                results
            } else {
                results
                field
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .task(id: query) {
            guard store.suggestionsEnabled, !tab.isPrivate, !isBrowsingQuery else {
                remote = []
                return
            }
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            let found = await SearchSuggestions.fetch(query)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.quick) { remote = found }
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: tab.isPrivate ? "eye.slash.fill" : "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tab.isPrivate ? Theme.ember : Theme.onInkMuted)
                TextField("Address", text: $store.addressDraft, prompt: Text("Search or enter address").foregroundColor(Theme.onInkMuted))
                    .font(Face.ui(16, weight: .medium))
                    .foregroundColor(Theme.onInk)
                    .tint(Theme.ember)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { submit(store.addressDraft) }
                if !store.addressDraft.isEmpty {
                    Button {
                        store.addressDraft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(Theme.onInkMuted)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                } else {
                    // System paste button: pastes without the "allow paste" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        DispatchQueue.main.async {
                            focused = false
                            store.open(text)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.barRaised)
                    .accessibilityLabel("Paste and go")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous)
                    .fill(Theme.bar)
                    .matchedGeometryEffect(id: "field", in: morph)
            )

            Button("Cancel") {
                focused = false
                store.endEditing()
            }
            .font(Face.ui(16, weight: .semibold))
            .foregroundColor(Theme.text)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(alignment: barOnTop ? .bottom : .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isBrowsingQuery {
                    if !library.bookmarks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle("Favorites")
                            FavoritesGrid(entries: Array(library.bookmarks.prefix(8)), compact: true) { entry in
                                store.open(entry.url)
                            }
                        }
                    }
                    let recent = library.recent(6)
                    if !recent.isEmpty && !tab.isPrivate {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Recent")
                            RowGroup {
                                ForEach(recent) { entry in
                                    EntryRow(entry: entry) { store.open(entry.url) }
                                }
                            }
                        }
                    }
                } else {
                    RowGroup {
                        SuggestionRow(symbol: goSymbol, title: goTitle, accent: true) { submit(query) }
                        ForEach(remote, id: \.self) { phrase in
                            SuggestionRow(symbol: "magnifyingglass", title: phrase) { submit(phrase) }
                        }
                    }
                    let matches = library.suggestions(for: query, limit: 6)
                    if !matches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("From your favorites & history")
                            RowGroup {
                                ForEach(matches) { entry in
                                    EntryRow(entry: entry) { store.open(entry.url) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .calmScroll()
    }

    private var resolvesToAddress: Bool {
        if Address.shortcut(in: query) != nil { return false }
        guard let url = Address.resolve(query) else { return false }
        return SearchEngine.allCases.allSatisfy { $0.url(for: query) != url }
    }

    private var goSymbol: String { resolvesToAddress ? "arrow.up.right.circle.fill" : "magnifyingglass.circle.fill" }

    private var goTitle: String {
        if let (shortcut, words) = Address.shortcut(in: query) { return "Search \(shortcut.name) for “\(words)”" }
        return resolvesToAddress ? "Go to \(Address.display(Address.resolve(query)))" : "Search \(SearchEngine.current.name) for “\(query)”"
    }

    private func submit(_ text: String) {
        focused = false
        Haptics.tap()
        store.open(text)
    }
}

/// Rows stacked on one rounded card with hairlines between them.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous)
                .fill(Theme.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
    }
}

struct SuggestionRow: View {
    let symbol: String
    let title: String
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: accent ? 20 : 15, weight: .semibold))
                    .foregroundColor(accent ? Theme.ember : Theme.muted)
                    .frame(width: 30)
                Text(title)
                    .font(Face.ui(16, weight: accent ? .semibold : .regular))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 56)
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Favicon(url: entry.url, title: entry.title, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(Face.ui(15, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(Address.display(entry.url))
                        .font(Face.ui(12))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 56)
        }
    }
}

/// Rows darken under a finger instead of flashing a system highlight.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.line : Color.clear)
    }
}
