import SwiftUI

/// All open tabs as live page previews. Tap to jump in, swipe a card sideways or tap × to close.
struct TabOverview: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var privateMode = false
    @State private var search = ""

    private var allTabs: [BrowserTab] { store.tabs.filter { $0.isPrivate == privateMode } }

    private var tabs: [BrowserTab] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allTabs }
        return allTabs.filter {
            $0.title.lowercased().contains(needle) || ($0.url?.absoluteString.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if allTabs.count > 3 { searchField }

            ScrollView {
                if tabs.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSize == .regular ? 210 : 150), spacing: 14)],
                        spacing: 20
                    ) {
                        ForEach(tabs) { tab in
                            TabCard(tab: tab, selected: tab.id == store.selectedID, store: store) {
                                store.select(tab)
                                store.hideOverview()
                            } close: {
                                Haptics.tap()
                                withAnimation(Motion.snappy) { store.close(tab) }
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }

            footer
        }
        .calmScroll()
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { privateMode = store.current?.isPrivate ?? false }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(privateMode ? "Private" : "Tabs")
                .font(Face.title(32, weight: .bold))
                .foregroundColor(Theme.text)
                .contentTransition(.opacity)
            Text("\(tabs.count)")
                .font(Face.ui(17, weight: .semibold))
                .foregroundColor(Theme.muted)
            Spacer()
            if store.canReopenClosedTab && !privateMode {
                Button {
                    Haptics.tap()
                    store.reopenClosedTab()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Reopen closed tab")
            }
            if !tabs.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        withAnimation(Motion.snappy) { store.closeAll(isPrivate: privateMode) }
                    } label: {
                        Label("Close all \(tabs.count) tabs", systemImage: "xmark")
                    }
                } label: {
                    Text("Close all")
                        .font(Face.ui(15, weight: .semibold))
                        .foregroundColor(Theme.muted)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.muted)
            TextField("Search tabs", text: $search)
                .font(Face.ui(15, weight: .medium))
                .foregroundColor(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: privateMode ? "eye.slash" : "square.on.square")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(Theme.muted)
            Text(privateMode ? "No private tabs" : "No tabs")
                .font(Face.title(22))
                .foregroundColor(Theme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ModeSwitch(privateMode: $privateMode)
            Spacer()
            Button {
                Haptics.tap()
                store.newTab(isPrivate: privateMode)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.onEmber)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.ember))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(privateMode ? "New private tab" : "New tab")

            Button {
                store.hideOverview()
            } label: {
                Text("Done")
                    .font(Face.ui(16, weight: .bold))
                    .foregroundColor(Theme.text)
                    .frame(minWidth: 56, minHeight: 50)
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Two-way switch between normal and private tabs; the ink thumb slides between them.
private struct ModeSwitch: View {
    @Binding var privateMode: Bool
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            segment("Tabs", symbol: "square.on.square", active: !privateMode) { privateMode = false }
            segment("Private", symbol: "eye.slash", active: privateMode) { privateMode = true }
        }
        .padding(4)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private func segment(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(title).font(Face.ui(14, weight: .bold))
            }
            .foregroundColor(active ? Theme.onInk : Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background {
                if active {
                    Capsule().fill(Theme.bar).matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let store: BrowserStore
    let open: () -> Void
    let close: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .overlay(alignment: .topTrailing) { closeButton }
            HStack(spacing: 7) {
                if tab.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.ember)
                }
                if tab.showsStartPage {
                    Circle().fill(Theme.ember).frame(width: 7, height: 7).padding(.horizontal, 4)
                } else {
                    Favicon(url: tab.url, title: tab.title, size: 16)
                }
                Text(cardTitle)
                    .font(Face.ui(13, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .offset(x: dragX)
        .opacity(1.0 - min(Double(abs(dragX)) / 260.0, 0.7))
        .rotationEffect(.degrees(Double(dragX) / 40))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            open()
        }
        .contextMenu {
            Button { store.togglePin(tab) } label: {
                Label(tab.pinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.pinned ? "pin.slash" : "pin")
            }
            Button { store.duplicate(tab) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            if let url = tab.url {
                Button {
                    UIPasteboard.general.url = url
                    store.showToast("Link copied")
                } label: { Label("Copy Link", systemImage: "link") }
            }
            Divider()
            Button(role: .destructive) { store.closeOthers(than: tab) } label: {
                Label("Close Other Tabs", systemImage: "xmark.square")
            }
            Button(role: .destructive, action: close) { Label("Close Tab", systemImage: "xmark") }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    dragX = value.translation.width
                }
                .onEnded { value in
                    if abs(dragX) > 110 {
                        withAnimation(Motion.snappy) { dragX = dragX > 0 ? 600 : -600 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { close() }
                    } else {
                        withAnimation(Motion.snappy) { dragX = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardTitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close tab", close)
    }

    private var cardTitle: String {
        if tab.showsStartPage { return "New tab" }
        return tab.title.isEmpty ? Address.display(tab.url) : tab.title
    }

    private var preview: some View {
        Color.clear
            .aspectRatio(0.74, contentMode: .fit)
            .overlay(alignment: .top) {
                if let snapshot = tab.snapshot, !tab.showsStartPage {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous)
                    .stroke(selected ? Theme.ember : Theme.line, lineWidth: selected ? 3 : 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }

    private var placeholder: some View {
        ZStack {
            Theme.card
            if tab.showsStartPage {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("Crowser")
                        .font(Face.title(18, weight: .bold))
                        .foregroundColor(Theme.text)
                    Circle().fill(Theme.ember).frame(width: 5, height: 5).padding(.leading, 2)
                }
            } else {
                Favicon(url: tab.url, title: tab.title, size: 46)
            }
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(Theme.onInk)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.ink.opacity(0.85)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close tab")
    }
}
