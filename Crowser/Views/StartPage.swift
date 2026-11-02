import SwiftUI

/// A new tab: greeting, favorites as icon tiles, and recent pages on a card.
struct StartPage: View {
    let isPrivate: Bool
    let bottomClearance: CGFloat

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var appeared = false

    private var wide: Bool { horizontalSize == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                masthead

                searchCard

                if isPrivate { privateNote }

                if !library.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Favorites")
                        FavoritesGrid(entries: Array(library.bookmarks.prefix(wide ? 16 : 12))) { store.open($0.url) }
                    }
                }

                let recent = isPrivate ? [] : library.recent(wide ? 8 : 5)
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Recently visited", trailing: "\(recent.count)")
                        RowGroup {
                            ForEach(recent) { entry in
                                EntryRow(entry: entry) { store.open(entry.url) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, wide ? 40 : 20)
            .padding(.top, wide ? 36 : 22)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .calmScroll()
        .background(Theme.paper)
        .onAppear { withAnimation(Motion.soft) { appeared = true } }
    }

    private var masthead: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("Crowser")
                    .font(Face.title(wide ? 44 : 36, weight: .bold))
                    .foregroundColor(Theme.text)
                Circle()
                    .fill(Theme.ember)
                    .frame(width: wide ? 10 : 8, height: wide ? 10 : 8)
                    .padding(.leading, 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crowser")
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(Self.greeting)
                .font(Face.ui(14, weight: .medium))
                .foregroundColor(Theme.muted)
        }
    }

    /// A big, thumb-friendly way in: tapping it opens the address panel.
    private var searchCard: some View {
        Button {
            Haptics.tap()
            store.beginEditing()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isPrivate ? "eye.slash.fill" : "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isPrivate ? Theme.ember : Theme.onInkMuted)
                Text(isPrivate ? "Search privately" : "Search or enter address")
                    .font(Face.ui(17, weight: .semibold))
                    .foregroundColor(Theme.onInkMuted)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.ember)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.bar)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.barEdge, lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityLabel("Search or enter address")
    }

    private var privateNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.ember)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text("Private tab")
                    .font(Face.ui(16, weight: .bold))
                    .foregroundColor(Theme.onInk)
                Text("No history, cookies or site data are kept once you close it.")
                    .font(Face.ui(14))
                    .foregroundColor(Theme.onInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bar))
    }

    private static var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Night owl hours"
        }
    }
}

/// Shown over a tab whose page couldn't load.
struct ErrorPage: View {
    let error: BrowserTab.LoadError
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: error.offline ? "wifi.slash" : "exclamationmark.bubble")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Theme.ember)
            Text(error.offline ? "You're offline" : "Can't open this page")
                .font(Face.title(30, weight: .bold))
                .foregroundColor(Theme.text)
            if let url = error.url {
                Text(Address.display(url))
                    .font(Face.ui(16, weight: .semibold))
                    .foregroundColor(Theme.muted)
            }
            Text(error.message)
                .font(Face.ui(15))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                retry()
            } label: {
                Text("Try again")
                    .font(Face.ui(16, weight: .bold))
                    .foregroundColor(Theme.onInk)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Capsule().fill(Theme.bar))
            }
            .buttonStyle(PressStyle())
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
