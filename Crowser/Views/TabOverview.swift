import SwiftUI

/// All open tabs as live page previews. Tap to jump in, swipe a card sideways or tap × to close.
struct TabOverview: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var privateMode = false

    private var tabs: [BrowserTab] { store.tabs.filter { $0.isPrivate == privateMode } }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                if tabs.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSize == .regular ? 210 : 150), spacing: 14)],
                        spacing: 20
                    ) {
                        ForEach(tabs) { tab in
                            TabCard(tab: tab, selected: tab.id == store.selectedID) {
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
                    .foregroundColor(Theme.onInk)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.ink))
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
                    Capsule().fill(Theme.ink).matchedGeometryEffect(id: "thumb", in: thumb)
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
    let open: () -> Void
    let close: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .overlay(alignment: .topTrailing) { closeButton }
            HStack(spacing: 7) {
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
