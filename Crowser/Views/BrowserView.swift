import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @Environment(\.scenePhase) private var scenePhase

    /// iPad and wide windows put the chrome on top; phones keep it under the thumb.
    private var chromeOnTop: Bool { horizontalSize == .regular }

    var body: some View {
        VStack(spacing: 0) {
            if let tab = store.current {
                if chromeOnTop { ChromeBar(tab: tab, placement: .top) }
                ZStack {
                    TabContent(tab: tab)
                        .id(tab.id)
                    if store.isEditingAddress {
                        SuggestionList(query: store.addressDraft)
                            .transition(.opacity)
                    }
                }
                if !chromeOnTop { ChromeBar(tab: tab, placement: .bottom) }
            }
        }
        .background(Rookery.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: store.isEditingAddress)
        .sheet(item: $store.sheet) { sheet in
            Group {
                switch sheet {
                case .tabs: TabsSheet()
                case .library: LibrarySheet()
                case .settings: SettingsSheet()
                }
            }
            .environmentObject(store)
            .environmentObject(library)
            .tint(Rookery.ember)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.persist() }
        }
    }
}

private struct TabContent: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        Group {
            if tab.url == nil {
                StartPage(isPrivate: tab.isPrivate)
            } else {
                WebViewContainer(webView: tab.webView)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
