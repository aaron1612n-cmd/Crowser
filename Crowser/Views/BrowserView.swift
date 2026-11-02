import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @Environment(\.scenePhase) private var scenePhase

    /// iPad and wide windows keep the bar on top; phones keep it under the thumb.
    private var barOnTop: Bool { horizontalSize == .regular }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            if let tab = store.current {
                TabStage(tab: tab, barOnTop: barOnTop)
                    .scaleEffect(store.showingOverview ? 0.9 : 1)
                    .opacity(store.showingOverview ? 0 : 1)
                    .allowsHitTesting(!store.showingOverview)
            }

            if store.showingOverview {
                TabOverview()
                    .transition(.scale(scale: 1.06).combined(with: .opacity))
                    .zIndex(1)
            }

            ToastView()
                .zIndex(2)
        }
        .sheet(item: $store.sheet) { sheet in
            Group {
                switch sheet {
                case .library: LibrarySheet()
                case .settings: SettingsSheet()
                case .more: MorePanel()
                }
            }
            .environmentObject(store)
            .environmentObject(library)
            .tint(Theme.ember)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.persist() }
        }
    }
}

/// One tab on screen: the page (or start page), the floating bar, and the address editor.
private struct TabStage: View {
    @ObservedObject var tab: BrowserTab
    let barOnTop: Bool

    @EnvironmentObject private var store: BrowserStore
    @Namespace private var morph

    static let barClearance: CGFloat = 78

    var body: some View {
        ZStack(alignment: barOnTop ? .top : .bottom) {
            content
                .padding(.top, barOnTop ? 66 : 0)
                .ignoresSafeArea(.container, edges: barOnTop ? [] : .bottom)

            if store.isEditingAddress {
                AddressEditor(tab: tab, barOnTop: barOnTop, morph: morph)
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                FloatingBar(tab: tab, barOnTop: barOnTop, morph: morph)
                    .transition(.opacity)
            }
        }
        .onAppear { tab.setBottomInset(barOnTop ? 0 : Self.barClearance) }
        .task(id: tab.id) { tab.activate() }
        .onChange(of: barOnTop) { onTop in tab.setBottomInset(onTop ? 0 : Self.barClearance) }
    }

    @ViewBuilder
    private var content: some View {
        if tab.showsStartPage {
            StartPage(isPrivate: tab.isPrivate, bottomClearance: barOnTop ? 24 : Self.barClearance + 12)
        } else {
            WebViewContainer(webView: tab.webView)
                .overlay {
                    if let error = tab.loadError {
                        ErrorPage(error: error) { tab.reload() }
                            .transition(.opacity)
                    }
                }
                .animation(Motion.quick, value: tab.loadError)
        }
    }
}

/// Short confirmation that drops in from the top ("Link copied").
private struct ToastView: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        VStack {
            if let message = store.toast {
                Text(message)
                    .font(Face.ui(14, weight: .semibold))
                    .foregroundColor(Theme.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.bar))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}
