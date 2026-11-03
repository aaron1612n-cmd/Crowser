import SwiftUI

/// The "…" panel: page actions as large tiles, text size, and the way to everything else.
struct MorePanel: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    private var tab: BrowserTab? { store.current }

    var body: some View {
        if let tab {
            Content(tab: tab, speaker: Speaker.shared, dismiss: { dismiss() })
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
                .modifier(SheetChrome())
        }
    }

    private struct Content: View {
        @ObservedObject var tab: BrowserTab
        @ObservedObject var speaker: Speaker
        let dismiss: () -> Void

        @EnvironmentObject private var store: BrowserStore
        @EnvironmentObject private var library: Library
        @EnvironmentObject private var prefs: Prefs
        @State private var cookies = 0

        private var hasPage: Bool { tab.url != nil && !tab.showsStartPage }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ActionTile("Share", symbol: "square.and.arrow.up", enabled: hasPage) {
                            after { if let url = tab.url { Presenter.share([Address.cleaned(url) ?? url]) } }
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
                        ActionTile(tab.readerOn ? "Exit reader" : "Reader", symbol: "doc.plaintext", highlighted: tab.readerOn, enabled: hasPage) {
                            dismiss()
                            tab.toggleReader()
                        }
                        ActionTile("Translate", symbol: "character.bubble", enabled: hasPage) {
                            dismiss()
                            tab.translate()
                        }
                        ActionTile(speaker.isSpeaking ? "Stop" : "Read aloud", symbol: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2", highlighted: speaker.isSpeaking, enabled: hasPage || speaker.isSpeaking) {
                            tab.readAloud()
                        }
                        ActionTile("PDF", symbol: "doc.richtext", enabled: hasPage) {
                            after { tab.saveAsPDF() }
                        }
                        ActionTile(tab.zapping ? "Cancel" : "Hide item", symbol: "eye.slash.circle", highlighted: tab.zapping, enabled: hasPage) {
                            dismiss()
                            tab.toggleZapper()
                        }
                        ActionTile("Source", symbol: "chevron.left.forwardslash.chevron.right", enabled: hasPage) {
                            after { tab.viewSource() }
                        }
                        ActionTile("Copy link", symbol: "link", enabled: hasPage) {
                            if let url = tab.url { UIPasteboard.general.url = Address.cleaned(url) ?? url }
                            dismiss()
                            store.showToast("Link copied")
                        }
                        ActionTile(tab.pinned ? "Unpin" : "Pin tab", symbol: tab.pinned ? "pin.slash" : "pin", highlighted: tab.pinned) {
                            store.togglePin(tab)
                        }
                        ActionTile("Duplicate", symbol: "plus.square.on.square", enabled: hasPage) {
                            dismiss()
                            store.duplicate(tab)
                        }
                        ActionTile("Reopen", symbol: "arrow.uturn.backward", enabled: store.canReopenClosedTab) {
                            dismiss()
                            store.reopenClosedTab()
                        }
                        ActionTile("Private", symbol: "eye.slash") {
                            dismiss()
                            store.newTab(isPrivate: true)
                        }
                        ActionTile("Library", symbol: "books.vertical") {
                            after { store.sheet = .library }
                        }
                        ActionTile("Hide bar", symbol: "rectangle.bottomhalf.inset.filled") {
                            dismiss()
                            store.tuckBar()
                        }
                    }

                    HStack(spacing: 10) {
                        textSize
                        refreshMenu
                    }
                    .opacity(hasPage ? 1 : 0.4)
                    .disabled(!hasPage)

                    if hasPage { thisSite }

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
                        .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(Theme.card))
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 20)
            }
            .calmScroll()
            .background(Theme.paper.ignoresSafeArea())
            .task(id: tab.url) { cookies = hasPage ? await tab.cookieCount() : 0 }
        }

        private var refreshMenu: some View {
            Menu {
                Picker("Auto-refresh", selection: Binding(get: { tab.autoRefresh }, set: { tab.setAutoRefresh($0) })) {
                    Text("Off").tag(0)
                    Text("Every 10 seconds").tag(10)
                    Text("Every 30 seconds").tag(30)
                    Text("Every minute").tag(60)
                    Text("Every 5 minutes").tag(300)
                    Text("Every 15 minutes").tag(900)
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tab.autoRefresh > 0 ? Theme.ember : Theme.text)
                    Text(tab.autoRefresh > 0 ? refreshLabel : "Refresh")
                        .font(Face.ui(11, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .monospacedDigit()
                }
                .frame(width: 76, height: 50)
                .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(Theme.card))
            }
            .accessibilityLabel("Auto-refresh")
        }

        private var refreshLabel: String {
            tab.autoRefresh < 60 ? "\(tab.autoRefresh)s" : "\(tab.autoRefresh / 60)m"
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
            .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(Theme.card))
        }

        /// Settings Crowser remembers for this website.
        private var thisSite: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This site")
                        .font(Face.title(20))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(Address.display(tab.url))
                        .font(Face.ui(13, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                RowGroup {
                    Button {
                        after { store.sheet = .shields }
                    } label: {
                        NavRow(
                            tab.shieldsDown ? "Shields down" : "Shields up",
                            detail: tab.shieldsDown ? "Every protection is off on this site." : "\(cookies) cookie\(cookies == 1 ? "" : "s") stored · \(tab.isSecure ? "Secure connection" : "Not secure")",
                            symbol: tab.shieldsDown ? "shield.slash.fill" : "checkmark.shield.fill",
                            lit: !tab.shieldsDown
                        )
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    SwitchRow(
                        "Game mode",
                        detail: "No text selection, hold menus, zoom or swipe-back. Full screen, screen stays on.",
                        symbol: "gamecontroller.fill",
                        isOn: tab.gameMode
                    ) {
                        tab.toggleGameMode()
                        if tab.gameMode { dismiss() }
                    }
                    if tab.gameMode {
                        SwitchRow("Lock page scrolling", detail: "Dragging only moves the game, never the page.", symbol: "lock.fill", isOn: tab.scrollLocked) {
                            tab.toggleScrollLock()
                        }
                    }
                    SwitchRow("Dark page", detail: "Turns light pages dark. Photos stay natural.", symbol: "moon.fill", isOn: tab.darkPage) {
                        tab.toggleDarkPage()
                    }
                    SwitchRow("JavaScript", detail: tab.javaScriptOn ? nil : "Off: faster and quieter, but some sites break.", symbol: "curlybraces", isOn: tab.javaScriptOn) {
                        tab.toggleJavaScript()
                    }
                    SwitchRow("Desktop version", detail: nil, symbol: "desktopcomputer", isOn: tab.isDesktop) {
                        tab.toggleDesktop()
                    }
                    Button {
                        after { store.sheet = .siteCode }
                    } label: {
                        NavRow("Custom CSS & JavaScript", detail: "Restyle or script this site your way.", symbol: "paintbrush.pointed.fill", lit: false)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    if tab.hiddenCount > 0 {
                        Button {
                            tab.restoreHidden()
                        } label: {
                            NavRow("Show \(tab.hiddenCount) hidden item\(tab.hiddenCount == 1 ? "" : "s")", detail: nil, symbol: "eye", lit: false)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                    Button {
                        Task { await tab.clearSiteData() }
                        dismiss()
                    } label: {
                        NavRow("Clear this site's data", detail: "Cookies, storage and cache for \(Address.display(tab.url)) only.", symbol: "trash", lit: false)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
        }

        /// Close the panel first, then act, so the next screen doesn't fight the dismissal.
        private func after(_ action: @escaping () -> Void) {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
        }
    }
}

struct SwitchRow: View {
    let title: String
    let detail: String?
    let symbol: String
    let isOn: Bool
    let toggle: () -> Void

    init(_ title: String, detail: String?, symbol: String, isOn: Bool, toggle: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.isOn = isOn
        self.toggle = toggle
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn ? Theme.onEmber : Theme.text)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.r(9), style: .continuous).fill(isOn ? Theme.ember : Theme.line))
                .animation(Motion.quick, value: isOn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Face.ui(16, weight: .semibold))
                    .foregroundColor(Theme.text)
                if let detail {
                    Text(detail)
                        .font(Face.ui(12))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .labelsHidden()
                .tint(Theme.ember)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 58)
        }
    }
}

/// A row that opens something or does one thing.
struct NavRow: View {
    let title: String
    let detail: String?
    let symbol: String
    let lit: Bool

    init(_ title: String, detail: String?, symbol: String, lit: Bool) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.lit = lit
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(lit ? Theme.onEmber : Theme.text)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.r(9), style: .continuous).fill(lit ? Theme.ember : Theme.line))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Face.ui(16, weight: .semibold))
                    .foregroundColor(Theme.text)
                if let detail {
                    Text(detail)
                        .font(Face.ui(12))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 58)
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
            .background(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous).fill(Theme.card))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous))
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
                .presentationCornerRadius(max(10, Theme.r(28)))
        } else {
            content
        }
    }
}
