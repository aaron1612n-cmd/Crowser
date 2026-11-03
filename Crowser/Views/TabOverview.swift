import SwiftUI

/// All open tabs as live page previews. Tap to jump in, swipe a card sideways or tap × to close.
struct TabOverview: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var privateMode = false
    @State private var search = ""
    @AppStorage("crowser.tabList") private var listStyle = false

    private var groupFilter: UUID? { privateMode ? nil : store.activeGroupID }

    private var allTabs: [BrowserTab] {
        store.tabs.filter { $0.isPrivate == privateMode && (groupFilter == nil || $0.groupID == groupFilter) }
    }

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
            if !privateMode && (!store.groups.isEmpty || store.tabs.count > 1) { groupStrip }
            if allTabs.count > 3 { searchField }

            ScrollView {
                if privateMode && store.privateLocked && !tabs.isEmpty {
                    lockedState
                } else if tabs.isEmpty {
                    emptyState
                } else if listStyle {
                    LazyVStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            TabRow(tab: tab, selected: tab.id == store.selectedID, store: store) {
                                store.select(tab)
                                store.hideOverview()
                            } close: {
                                Haptics.tap()
                                withAnimation(Motion.snappy) { store.close(tab) }
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
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
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { listStyle.toggle() }
            } label: {
                Image(systemName: listStyle ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(listStyle ? "Show as grid" : "Show as list")
            if !privateMode { sessionsMenu }
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
                        withAnimation(Motion.snappy) {
                            if let id = groupFilter, let group = store.groups.first(where: { $0.id == id }) {
                                store.closeGroup(group)
                            } else {
                                store.closeAll(isPrivate: privateMode)
                            }
                        }
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

    /// Saved sessions: save what's open, reopen or delete earlier ones.
    private var sessionsMenu: some View {
        Menu {
            Button {
                Task {
                    let name = await Presenter.prompt(title: "Save tabs", message: "Name this session", defaultText: store.groups.first { $0.id == store.activeGroupID }?.name)
                    if let name { store.saveSession(named: name) }
                }
            } label: {
                Label(store.activeGroupID == nil ? "Save All Tabs as Session" : "Save This Group as Session", systemImage: "square.and.arrow.down.on.square")
            }
            if !store.sessions.isEmpty {
                Divider()
                ForEach(store.sessions) { session in
                    Menu {
                        Button { store.openSession(session) } label: { Label("Open \(session.links.count) Tabs", systemImage: "arrow.up.forward.square") }
                        Button(role: .destructive) { store.deleteSession(session) } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Label("\(session.name) · \(session.links.count)", systemImage: "tray.full")
                    }
                }
            }
        } label: {
            Image(systemName: "tray.full")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.muted)
                .frame(width: 40, height: 44)
        }
        .accessibilityLabel("Sessions")
    }

    /// Group chips: All, each group, and a way to start a new one.
    private var groupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", count: store.tabs.filter { !$0.isPrivate }.count, tone: nil, active: store.activeGroupID == nil) {
                    store.activeGroupID = nil
                }
                ForEach(store.groups) { group in
                    chip(title: group.name, count: store.tabs.filter { $0.groupID == group.id }.count, tone: Theme.groupTones[group.tone % Theme.groupTones.count], active: store.activeGroupID == group.id) {
                        store.activeGroupID = group.id
                    }
                    .contextMenu {
                        Button {
                            Task {
                                if let name = await Presenter.prompt(title: "Rename group", message: "", defaultText: group.name) {
                                    store.renameGroup(group, to: name)
                                }
                            }
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button { store.recolorGroup(group) } label: { Label("Change Color", systemImage: "paintpalette") }
                        Button {
                            store.activeGroupID = group.id
                            store.saveSession(named: group.name)
                        } label: { Label("Save as Session", systemImage: "square.and.arrow.down.on.square") }
                        Divider()
                        Button { store.ungroup(group) } label: { Label("Ungroup Tabs", systemImage: "rectangle.stack.badge.minus") }
                        Button(role: .destructive) { withAnimation(Motion.snappy) { store.closeGroup(group) } } label: {
                            Label("Close Group's Tabs", systemImage: "xmark")
                        }
                    }
                }
                Button {
                    Task {
                        if let name = await Presenter.prompt(title: "New group", message: "Name it, like Games or School", defaultText: nil) {
                            withAnimation(Motion.snappy) { store.createGroup(named: name, with: store.current?.isPrivate == false ? store.current : nil) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .heavy))
                        Text("Group").font(Face.ui(13, weight: .bold))
                    }
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .overlay(Capsule().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("New group")
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func chip(title: String, count: Int, tone: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                if let tone {
                    Circle().fill(tone).frame(width: 9, height: 9)
                }
                Text(title)
                    .font(Face.ui(13, weight: .bold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(Face.ui(12, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundColor(active ? Theme.onInk : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(active ? Theme.bar : Theme.card))
            .overlay(Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(active ? .isSelected : [])
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

    private var lockedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Theme.ember)
            Text("\(tabs.count) private tabs, locked")
                .font(Face.title(20, weight: .bold))
                .foregroundColor(Theme.text)
            Button {
                Task { await store.unlockPrivate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(Face.ui(16, weight: .bold))
                    .foregroundColor(Theme.onEmber)
                    .frame(width: 180, height: 48)
                    .background(Capsule().fill(Theme.ember))
            }
            .buttonStyle(PressStyle())
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
            .contextMenu {
                if !store.closedPages.isEmpty {
                    Section("Recently closed") {
                        ForEach(Array(store.closedPages.reversed().prefix(10).enumerated()), id: \.offset) { _, page in
                            Button { store.reopen(page) } label: {
                                Label(Address.display(page), systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
                Button { store.newTab(isPrivate: !privateMode) } label: {
                    Label(privateMode ? "New Tab" : "New Private Tab", systemImage: privateMode ? "plus.square" : "eye.slash")
                }
            }

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
                if let group = store.group(for: tab) {
                    Capsule()
                        .fill(Theme.groupTones[group.tone % Theme.groupTones.count])
                        .frame(width: 4, height: 14)
                }
                if tab.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.ember)
                }
                if tab.sleeping {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.muted)
                        .accessibilityLabel("Asleep")
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
            if !tab.isPrivate { GroupMenu(tab: tab, store: store) }
            if UIDevice.current.userInterfaceIdiom == .pad && tab.id != store.selectedID {
                Button {
                    store.split(with: tab)
                    store.hideOverview()
                } label: { Label("Open in Split View", systemImage: "rectangle.split.2x1") }
            }
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

/// "Move to group" choices for one tab.
private struct GroupMenu: View {
    let tab: BrowserTab
    let store: BrowserStore

    var body: some View {
        Menu {
            ForEach(store.groups) { group in
                Button { store.move(tab, to: group) } label: {
                    Label(group.name, systemImage: tab.groupID == group.id ? "checkmark" : "circle.fill")
                }
            }
            Button {
                Task {
                    if let name = await Presenter.prompt(title: "New group", message: "Name it, like Games or School", defaultText: nil) {
                        store.createGroup(named: name, with: tab)
                    }
                }
            } label: { Label("New Group…", systemImage: "plus") }
            if tab.groupID != nil {
                Divider()
                Button { store.move(tab, to: nil) } label: { Label("Remove from Group", systemImage: "rectangle.stack.badge.minus") }
            }
        } label: {
            Label("Move to Group", systemImage: "rectangle.stack")
        }
    }
}

/// One tab as a row in the list layout.
private struct TabRow: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let store: BrowserStore
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(selected ? Theme.ember : (store.group(for: tab).map { Theme.groupTones[$0.tone % Theme.groupTones.count] } ?? Color.clear))
                .frame(width: 4, height: 34)
            if tab.showsStartPage {
                Circle().fill(Theme.ember).frame(width: 8, height: 8).frame(width: 28, height: 28)
            } else {
                Favicon(url: tab.url, title: tab.title, size: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if tab.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.ember)
                    }
                    if tab.sleeping {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted)
                    }
                    Text(title)
                        .font(Face.ui(15, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                }
                Text(tab.showsStartPage ? "Start page" : Address.display(tab.url))
                    .font(Face.ui(12))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if tab.isLoading {
                ProgressView().controlSize(.small)
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(Theme.muted)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close tab")
        }
        .padding(.leading, 8)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(selected ? Theme.card : Theme.card.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).stroke(Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            open()
        }
        .contextMenu {
            Button { store.togglePin(tab) } label: { Label(tab.pinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.pinned ? "pin.slash" : "pin") }
            Button { store.duplicate(tab) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            if !tab.isPrivate { GroupMenu(tab: tab, store: store) }
            if UIDevice.current.userInterfaceIdiom == .pad && tab.id != store.selectedID {
                Button {
                    store.split(with: tab)
                    store.hideOverview()
                } label: { Label("Open in Split View", systemImage: "rectangle.split.2x1") }
            }
            Divider()
            Button(role: .destructive) { store.closeOthers(than: tab) } label: { Label("Close Other Tabs", systemImage: "xmark.square") }
            Button(role: .destructive, action: close) { Label("Close Tab", systemImage: "xmark") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        if tab.showsStartPage { return "New tab" }
        return tab.title.isEmpty ? Address.display(tab.url) : tab.title
    }
}
