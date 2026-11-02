import SwiftUI
import WebKit

/// The crow-black bar that floats over the page.
/// Scroll down and it folds into a small pill showing the site; swipe it sideways to change tabs.
struct FloatingBar: View {
    @ObservedObject var tab: BrowserTab
    let barOnTop: Bool
    let morph: Namespace.ID

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @GestureState private var swipe: CGFloat = 0

    private var collapsed: Bool { tab.barCollapsed && !tab.showsStartPage }

    var body: some View {
        Group {
            if collapsed {
                collapsedPill
            } else {
                expandedBar
            }
        }
        .animation(Motion.snappy, value: collapsed)
        .padding(.horizontal, barOnTop ? 16 : 10)
        .padding(barOnTop ? .top : .bottom, barOnTop ? 8 : 4)
        .frame(maxWidth: barOnTop ? 820 : 560)
        .frame(maxWidth: .infinity)
    }

    // MARK: Expanded

    private var expandedBar: some View {
        HStack(spacing: 2) {
            navButton(back: true)
            navButton(back: false)
            addressPill
                .padding(.horizontal, 4)
            tabsButton
            moreButton
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.bar)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.barEdge, lineWidth: 1))
                .matchedGeometryEffect(id: "bar", in: morph)
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        )
        .overlay(alignment: barOnTop ? .bottom : .top) {
            LoadLine(progress: tab.progress, isLoading: tab.isLoading)
                .padding(.horizontal, 22)
        }
        .environment(\.colorScheme, .dark)
    }

    private var addressPill: some View {
        HStack(spacing: 8) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tab.isPrivate ? Theme.ember : Theme.onInkMuted)
            Text(addressText)
                .font(Face.ui(15, weight: .semibold))
                .foregroundColor(tab.url == nil ? Theme.onInkMuted : Theme.onInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if tab.url != nil && !tab.showsStartPage {
                Button {
                    tab.isLoading ? tab.stop() : tab.reload()
                    Haptics.tap()
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.onInk)
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(tab.isLoading ? "Stop" : "Reload")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.barRaised)
                .matchedGeometryEffect(id: "field", in: morph)
        )
        .offset(x: swipe)
        .contentShape(Rectangle())
        .onTapGesture { store.beginEditing() }
        .gesture(swipeTabs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.url == nil ? "Search or enter address" : "Address, \(addressText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Next tab") { store.selectAdjacent(1) }
        .accessibilityAction(named: "Previous tab") { store.selectAdjacent(-1) }
    }

    private var swipeTabs: some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($swipe) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width * 0.55
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(Motion.snappy) {
                    if value.translation.width < -70 {
                        store.selectAdjacent(1, createAtEnd: true)
                    } else if value.translation.width > 70 {
                        store.selectAdjacent(-1, createAtEnd: true)
                    }
                }
            }
    }

    private var addressText: String {
        if tab.url == nil || tab.showsStartPage { return "Search or enter address" }
        return Address.display(tab.url)
    }

    private var leadingSymbol: String {
        if tab.isPrivate { return "eye.slash.fill" }
        if tab.url == nil || tab.showsStartPage { return "magnifyingglass" }
        return tab.isSecure ? "lock.fill" : "exclamationmark.triangle.fill"
    }

    @ViewBuilder
    private func navButton(back: Bool) -> some View {
        let enabled = back ? tab.canGoBack : tab.canGoForward
        let items: [WKBackForwardListItem] = back
            ? Array(tab.webView.backForwardList.backList.reversed())
            : tab.webView.backForwardList.forwardList
        Menu {
            ForEach(Array(items.prefix(12)), id: \.self) { item in
                Button(item.title?.isEmpty == false ? item.title! : Address.display(item.url)) {
                    tab.go(to: item)
                }
            }
        } label: {
            Image(systemName: back ? "chevron.backward" : "chevron.forward")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(enabled ? Theme.onInk : Theme.onInkMuted.opacity(0.4))
                .frame(width: 40, height: 42)
                .contentShape(Rectangle())
        } primaryAction: {
            back ? tab.goBack() : tab.goForward()
        }
        .disabled(!enabled)
        .accessibilityLabel(back ? "Back" : "Forward")
    }

    private var tabsButton: some View {
        Button {
            Haptics.tap()
            store.showOverview()
        } label: {
            Text(store.tabs.count > 99 ? "∞" : "\(store.tabs.count)")
                .font(Face.ui(13, weight: .bold))
                .contentTransition(.numericText())
                .animation(Motion.snappy, value: store.tabs.count)
                .foregroundColor(Theme.onInk)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.onInk, lineWidth: 1.8)
                )
                .frame(width: 40, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            Button { store.newTab() } label: { Label("New Tab", systemImage: "plus.square.on.square") }
            Button { store.newTab(isPrivate: true) } label: { Label("New Private Tab", systemImage: "eye.slash") }
            if store.canReopenClosedTab {
                Button { store.reopenClosedTab() } label: { Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward") }
            }
            Divider()
            Button(role: .destructive) { store.closeCurrent() } label: { Label("Close This Tab", systemImage: "xmark") }
        }
        .accessibilityLabel("Tabs, \(store.tabs.count) open")
    }

    private var moreButton: some View {
        Button {
            Haptics.tap()
            store.sheet = .more
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.onInk)
                .frame(width: 40, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("More")
    }

    // MARK: Collapsed

    private var collapsedPill: some View {
        Button {
            tab.setCollapsed(false)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.isPrivate ? "eye.slash.fill" : (tab.isSecure ? "lock.fill" : "globe"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tab.isPrivate ? Theme.ember : Theme.onInkMuted)
                Text(Address.display(tab.url))
                    .font(Face.ui(13, weight: .semibold))
                    .foregroundColor(Theme.onInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.bar)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.barEdge, lineWidth: 1))
                    .matchedGeometryEffect(id: "bar", in: morph)
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
            )
            .overlay(alignment: barOnTop ? .bottom : .top) {
                LoadLine(progress: tab.progress, isLoading: tab.isLoading)
                    .padding(.horizontal, 14)
            }
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .frame(maxWidth: 260)
        .accessibilityLabel("Show toolbar, \(Address.display(tab.url))")
    }
}

/// The ember line that runs along the bar's edge while a page loads, finishes its run, then lets go.
struct LoadLine: View {
    let progress: Double
    let isLoading: Bool

    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.ember)
                .frame(width: max(6, geo.size.width * fraction), height: 2.5)
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .frame(height: 2.5)
        .allowsHitTesting(false)
        .onChange(of: isLoading) { loading in
            if loading {
                visible = true
            } else {
                withAnimation(.easeIn(duration: 0.45).delay(0.2)) { visible = false }
            }
        }
        .onAppear { visible = isLoading }
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        guard isLoading else { return visible ? 1 : 0 }
        return CGFloat(max(progress, 0.08))
    }
}
