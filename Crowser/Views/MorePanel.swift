import SwiftUI

/// The "…" panel: page actions as large tiles, text size, and the way to everything else.
struct MorePanel: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    private var tab: BrowserTab? { store.current }

    var body: some View {
        if let tab {
            Content(tab: tab, dismiss: { dismiss() })
                .presentationDetents([.height(500), .large])
                .presentationDragIndicator(.visible)
                .modifier(SheetChrome())
        }
    }

    private struct Content: View {
        @ObservedObject var tab: BrowserTab
        let dismiss: () -> Void

        @EnvironmentObject private var store: BrowserStore
        @EnvironmentObject private var library: Library

        private var hasPage: Bool { tab.url != nil && !tab.showsStartPage }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ActionTile("Share", symbol: "square.and.arrow.up", enabled: hasPage) {
                            after { if let url = tab.url { Presenter.share([url]) } }
                        }
                        ActionTile(
                            library.isBookmarked(tab.url) ? "Saved" : "Favorite",
                            symbol: library.isBookmarked(tab.url) ? "star.fill" : "star",
                            highlighted: library.isBookmarked(tab.url),
                            enabled: hasPage
                        ) {
                            store.toggleBookmarkForCurrent()
                        }
                        ActionTile("Find", symbol: "text.magnifyingglass", enabled: hasPage) {
                            after { tab.findOnPage() }
                        }
                        ActionTile(
                            tab.isDesktop ? "Mobile site" : "Desktop site",
                            symbol: tab.isDesktop ? "iphone" : "desktopcomputer",
                            enabled: hasPage
                        ) {
                            tab.toggleDesktop()
                            dismiss()
                        }
                        ActionTile("New tab", symbol: "plus.square") {
                            dismiss()
                            store.newTab()
                        }
                        ActionTile("Private", symbol: "eye.slash") {
                            dismiss()
                            store.newTab(isPrivate: true)
                        }
                        ActionTile("Copy link", symbol: "link", enabled: hasPage) {
                            UIPasteboard.general.url = tab.url
                            dismiss()
                            store.showToast("Link copied")
                        }
                        ActionTile("Library", symbol: "books.vertical") {
                            after { store.sheet = .library }
                        }
                    }

                    textSize
                        .opacity(hasPage ? 1 : 0.4)
                        .disabled(!hasPage)

                    Button {
                        after { store.sheet = .settings }
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 26)
                            Text("Settings")
                                .font(Face.ui(16, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.muted)
                        }
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 20)
            }
            .background(Theme.paper.ignoresSafeArea())
        }

        private var pageHeader: some View {
            HStack(spacing: 12) {
                if hasPage {
                    Favicon(url: tab.url, title: tab.title, size: 40)
                } else {
                    Circle().fill(Theme.ember).frame(width: 12, height: 12).frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasPage ? (tab.title.isEmpty ? Address.display(tab.url) : tab.title) : "New tab")
                        .font(Face.title(19))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if hasPage {
                        Text(Address.display(tab.url))
                            .font(Face.ui(13))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }

        private var textSize: some View {
            HStack(spacing: 0) {
                Button { tab.stepZoom(-1) } label: {
                    Text("A").font(Face.ui(14, weight: .bold)).frame(width: 60, height: 50)
                }
                .accessibilityLabel("Smaller text")
                Rectangle().fill(Theme.line).frame(width: 1, height: 26)
                Button { tab.resetZoom(); Haptics.select() } label: {
                    Text("\(Int((tab.zoom * 100).rounded()))%")
                        .font(Face.ui(15, weight: .semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .accessibilityLabel("Text size \(Int((tab.zoom * 100).rounded())) percent, reset")
                Rectangle().fill(Theme.line).frame(width: 1, height: 26)
                Button { tab.stepZoom(1) } label: {
                    Text("A").font(Face.ui(20, weight: .bold)).frame(width: 60, height: 50)
                }
                .accessibilityLabel("Larger text")
            }
            .buttonStyle(PressStyle())
            .foregroundColor(Theme.text)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }

        /// Close the panel first, then act, so the next screen doesn't fight the dismissal.
        private func after(_ action: @escaping () -> Void) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
        }
    }
}

private struct ActionTile: View {
    let title: String
    let symbol: String
    var highlighted = false
    var enabled = true
    let action: () -> Void

    init(_ title: String, symbol: String, highlighted: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.highlighted = highlighted
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(highlighted ? Theme.ember : Theme.text)
                    .frame(height: 24)
                Text(title)
                    .font(Face.ui(12, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }
}

/// Paper background and softer corners on sheets where the OS supports it.
struct SheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackground(Theme.paper)
                .presentationCornerRadius(28)
        } else {
            content
        }
    }
}
