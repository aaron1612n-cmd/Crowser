import SwiftUI

/// The soot-black bar: address field plus controls.
/// On phones it sits at the bottom with the controls under the address; on iPad it is one row on top.
struct ChromeBar: View {
    enum Placement { case top, bottom }

    @ObservedObject var tab: BrowserTab
    let placement: Placement

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if placement == .bottom { ProgressLine(progress: tab.progress, isLoading: tab.isLoading) }

            Group {
                if placement == .top {
                    HStack(spacing: 18) {
                        backForward
                        addressRow
                        if !editing { trailingControls }
                    }
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 6) {
                        addressRow
                        if !editing {
                            HStack {
                                backForward
                                Spacer(minLength: 0)
                                trailingControls
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, 16)

            if placement == .top { ProgressLine(progress: tab.progress, isLoading: tab.isLoading) }
        }
        .background(Rookery.soot.ignoresSafeArea(edges: placement == .bottom ? .bottom : .top))
        .environment(\.colorScheme, .dark)
        .onChange(of: editing) { isEditing in
            store.isEditingAddress = isEditing
        }
        .onChange(of: store.isEditingAddress) { isEditing in
            if !isEditing { editing = false }
        }
        .onChange(of: store.addressFocusRequest) { _ in beginEditing() }
        .onAppear {
            if tab.url == nil && store.addressFocusRequest > 0 { beginEditing() }
        }
    }

    // MARK: Address

    private var addressRow: some View {
        HStack(spacing: 12) {
            addressField
            if editing {
                Button("Cancel") { editing = false }
                    .font(Face.mono(14))
                    .foregroundColor(Rookery.bone)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var addressField: some View {
        HStack(spacing: 10) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tab.isPrivate ? Rookery.ember : Rookery.ash)
                .frame(width: 14)

            ZStack(alignment: .leading) {
                TextField("Address", text: $store.addressDraft, prompt: Text("search or address").foregroundColor(Rookery.ash))
                    .font(Face.mono(15))
                    .foregroundColor(Rookery.bone)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($editing)
                    .onSubmit { store.open(store.addressDraft) }
                    .opacity(editing ? 1 : 0)

                if !editing {
                    Text(tab.url == nil ? "search or address" : Address.display(tab.url))
                        .font(Face.mono(15))
                        .foregroundColor(tab.url == nil ? Rookery.ash : Rookery.bone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(tab.url == nil ? "Address" : "Address, \(Address.display(tab.url))")
                }
            }

            if editing {
                if !store.addressDraft.isEmpty {
                    BarButton(symbol: "xmark.circle.fill", label: "Clear", size: 15) { store.addressDraft = "" }
                }
            } else if tab.url != nil {
                BarButton(
                    symbol: tab.isLoading ? "xmark" : "arrow.clockwise",
                    label: tab.isLoading ? "Stop" : "Reload",
                    size: 14
                ) {
                    tab.isLoading ? tab.stop() : tab.reload()
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Rookery.feather)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(editing ? Rookery.ember : .clear)
                .frame(height: 1.5)
        }
    }

    private var leadingSymbol: String {
        if tab.isPrivate { return "eye.slash" }
        if editing { return "magnifyingglass" }
        guard let url = tab.url else { return "magnifyingglass" }
        return url.scheme == "https" ? "lock" : "lock.open"
    }

    private func beginEditing() {
        store.addressDraft = tab.url?.absoluteString ?? ""
        editing = true
    }

    // MARK: Controls

    private var backForward: some View {
        HStack(spacing: placement == .top ? 14 : 30) {
            BarButton(symbol: "chevron.left", label: "Back") { tab.goBack() }
                .disabled(!tab.canGoBack)
            BarButton(symbol: "chevron.right", label: "Forward") { tab.goForward() }
                .disabled(!tab.canGoForward)
        }
    }

    private var trailingControls: some View {
        HStack(spacing: placement == .top ? 18 : 30) {
            BarButton(
                symbol: library.isBookmarked(tab.url) ? "bookmark.fill" : "bookmark",
                label: library.isBookmarked(tab.url) ? "Remove bookmark" : "Bookmark",
                tint: library.isBookmarked(tab.url) ? Rookery.ember : Rookery.bone
            ) {
                store.toggleBookmarkForCurrent()
            }
            .disabled(tab.url == nil)

            Button { store.sheet = .tabs } label: {
                TabCount(count: store.tabs.count)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tabs, \(store.tabs.count) open")

            Menu {
                Button { store.newTab() } label: { SwiftUI.Label("New tab", systemImage: "plus") }
                Button { store.newTab(isPrivate: true) } label: { SwiftUI.Label("New private tab", systemImage: "eye.slash") }
                if let url = tab.url {
                    ShareLink(item: url) { SwiftUI.Label("Share", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button { store.sheet = .library } label: { SwiftUI.Label("Bookmarks & history", systemImage: "books.vertical") }
                Button { store.sheet = .settings } label: { SwiftUI.Label("Settings", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Rookery.bone)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
    }
}

/// Plain symbol button sized for thumbs (44pt target).
struct BarButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 17
    var tint: Color = Rookery.bone
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(isEnabled ? tint : Rookery.ash.opacity(0.45))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Tab counter: a square outline with the count set in serif.
struct TabCount: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "∞" : "\(count)")
            .font(Face.display(14, weight: .semibold))
            .foregroundColor(Rookery.bone)
            .frame(width: 24, height: 24)
            .overlay(Rectangle().stroke(Rookery.bone, lineWidth: 1.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
