import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var prefs: Prefs

    /// iPad and wide windows keep the bar on top; phones keep it under the thumb. Settings can force either.
    private var barOnTop: Bool {
        switch prefs.barPosition {
        case .top: return true
        case .bottom: return false
        case .auto: return horizontalSize == .regular
        }
    }

    /// Anything that changes how the interface is drawn. A change redraws everything with the new look.
    private var lookToken: String {
        "\(prefs.accent.rawValue)|\(prefs.barStyle.rawValue)|\(prefs.roundness)|\(prefs.compact)|\(prefs.textScale)|\(prefs.boldText)|\(prefs.highContrast)"
    }

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
        .id(lookToken)
        .tint(Theme.ember)
        .preferredColorScheme(prefs.appearance.scheme)
        .sheet(item: $store.sheet) { sheet in
            Group {
                switch sheet {
                case .library: LibrarySheet()
                case .settings: SettingsSheet()
                case .more: MorePanel()
                case .shields: ShieldsSheet()
                case .siteCode: SiteCodeSheet()
                }
            }
            .environmentObject(store)
            .environmentObject(library)
            .environmentObject(prefs)
            .environmentObject(store.sites)
            .tint(Theme.ember)
            .preferredColorScheme(prefs.appearance.scheme)
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

    private var collapsed: Bool { tab.barCollapsed && !tab.showsStartPage && !barOnTop }
    private var compact: Bool { Look.compact }

    var body: some View {
        ZStack(alignment: barOnTop ? .top : .bottom) {
            // The page and the bar sit one above the other; the bar never covers the page.
            // (Covering it meant padding every page, which made pages that should stay still scrollable.)
            VStack(spacing: 0) {
                if barOnTop && !tab.gameMode { barSlot }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !barOnTop && !tab.gameMode { barSlot }
            }

            if tab.gameMode { gameOverlay }

            if store.isEditingAddress {
                AddressEditor(tab: tab, barOnTop: barOnTop, morph: morph)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task(id: tab.id) { tab.activate() }
        .statusBarHidden(tab.gameMode)
        .persistentSystemOverlays(tab.gameMode ? .hidden : .automatic)
        .animation(Motion.snappy, value: tab.gameMode)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = tab.gameMode }
        .onChange(of: tab.gameMode) { on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Game mode: the page gets the whole screen. A small corner button brings the bar back.
    private var gameOverlay: some View {
        ZStack(alignment: barOnTop ? .top : .bottom) {
            Color.clear.allowsHitTesting(false)
            if tab.gameBarShown && !store.isEditingAddress {
                FloatingBar(tab: tab, barOnTop: barOnTop, morph: morph)
                    .padding(barOnTop ? .top : .bottom, 8)
                    .transition(.move(edge: barOnTop ? .top : .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { tab.gameBarShown.toggle() }
            } label: {
                Image(systemName: tab.gameBarShown ? "xmark" : "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.onInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.bar.opacity(0.6)))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.trailing, 8)
            .padding(.top, barOnTop && tab.gameBarShown ? 70 : 6)
            .accessibilityLabel(tab.gameBarShown ? "Hide toolbar" : "Show toolbar")
        }
    }

    private var barSlot: some View {
        ZStack {
            if !store.isEditingAddress {
                FloatingBar(tab: tab, barOnTop: barOnTop, morph: morph)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: barOnTop ? (compact ? 56 : 66) : (collapsed ? 44 : (compact ? 54 : 64)), alignment: barOnTop ? .top : .bottom)
        .background(Theme.paper.ignoresSafeArea(edges: barOnTop ? .top : .bottom))
        .animation(Motion.snappy, value: collapsed)
    }

    @ViewBuilder
    private var content: some View {
        if tab.showsStartPage {
            StartPage(isPrivate: tab.isPrivate, bottomClearance: 24)
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
