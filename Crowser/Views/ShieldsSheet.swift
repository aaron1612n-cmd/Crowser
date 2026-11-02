import SwiftUI

/// Shields: one big switch for this site, and every protection with its own switch.
struct ShieldsSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let tab = store.current {
            Content(tab: tab, dismiss: { dismiss() })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .modifier(SheetChrome())
        }
    }

    private struct Content: View {
        @ObservedObject var tab: BrowserTab
        let dismiss: () -> Void
        @EnvironmentObject private var store: BrowserStore
        @EnvironmentObject private var prefs: Prefs

        private var hasPage: Bool { tab.url != nil && !tab.showsStartPage }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Shields")
                            .font(Face.title(30, weight: .bold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if hasPage {
                            Text(Address.display(tab.url))
                                .font(Face.ui(13, weight: .semibold))
                                .foregroundColor(Theme.muted)
                                .lineLimit(1)
                        }
                    }

                    if hasPage { siteSwitch }

                    Text("Everywhere")
                        .font(Face.title(20))
                        .foregroundColor(Theme.text)
                        .padding(.top, 4)

                    RowGroup {
                        SwitchRow("Ads & trackers", detail: "Blocks known ad and tracking networks.", symbol: "hand.raised.fill", isOn: store.blockTrackers) {
                            store.blockTrackers.toggle()
                        }
                        SwitchRow("Cookie popups", detail: "Hides consent banners on most sites.", symbol: "checkmark.seal.fill", isOn: store.hideCookieBanners) {
                            store.hideCookieBanners.toggle()
                        }
                        SwitchRow("HTTPS only", detail: "Upgrades every site to a secure connection, falls back only if it has none.", symbol: "lock.fill", isOn: prefs.httpsOnly) {
                            prefs.httpsOnly.toggle()
                        }
                        SwitchRow("Fingerprint blocking", detail: "Hides device details and scrambles canvas reads trackers use to recognize you.", symbol: "touchid", isOn: prefs.fingerprinting) {
                            prefs.fingerprinting.toggle()
                            store.prefsChanged()
                        }
                        SwitchRow("Clean links", detail: "Strips utm_, fbclid, gclid and other tracking tags from addresses.", symbol: "link.badge.plus", isOn: prefs.cleanLinks) {
                            prefs.cleanLinks.toggle()
                        }
                        SwitchRow("Hide where you came from", detail: "Pages don't tell the next site which page sent you. Can break some sign-ins.", symbol: "arrow.uturn.left.circle.fill", isOn: prefs.stripReferrer) {
                            prefs.stripReferrer.toggle()
                            store.prefsChanged()
                        }
                        SwitchRow("Block popups", detail: "Only windows you tap to open are allowed.", symbol: "macwindow.badge.plus", isOn: prefs.blockPopups) {
                            prefs.blockPopups.toggle()
                            store.prefsChanged()
                        }
                        SwitchRow("Block autoplay", detail: "Videos wait for a tap. Applies to new tabs.", symbol: "play.slash.fill", isOn: prefs.blockAutoplay) {
                            prefs.blockAutoplay.toggle()
                        }
                        SwitchRow("Fraud warnings", detail: "Warns before known phishing and malware sites. Applies to new tabs.", symbol: "exclamationmark.triangle.fill", isOn: prefs.fraudWarnings) {
                            prefs.fraudWarnings.toggle()
                        }
                        SwitchRow("JavaScript", detail: "Off makes pages lighter and quieter, but many sites need it.", symbol: "curlybraces", isOn: prefs.javaScript) {
                            prefs.javaScript.toggle()
                            store.prefsChanged()
                        }
                    }

                    Text("Shields work on Apple's WebKit engine, which every iPhone browser has to use. Each site can drop them all with the switch above.")
                        .font(Face.ui(12))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .calmScroll()
            .background(Theme.paper.ignoresSafeArea())
        }

        /// The one switch: everything off for this site, or back on.
        private var siteSwitch: some View {
            Button {
                tab.toggleShields()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: tab.shieldsDown ? "shield.slash.fill" : "checkmark.shield.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(tab.shieldsDown ? Theme.text : Theme.onEmber)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tab.shieldsDown ? "Shields are down" : "Shields are up")
                            .font(Face.ui(19, weight: .heavy))
                        Text(tab.shieldsDown ? "Tap to protect this site again." : "Tap to turn every protection off here.")
                            .font(Face.ui(13, weight: .medium))
                            .opacity(0.8)
                    }
                    .foregroundColor(tab.shieldsDown ? Theme.text : Theme.onEmber)
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous)
                        .fill(tab.shieldsDown ? Theme.card : Theme.ember)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous)
                        .stroke(tab.shieldsDown ? Theme.line : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .animation(Motion.snappy, value: tab.shieldsDown)
            .accessibilityLabel(tab.shieldsDown ? "Shields down, turn on" : "Shields up, turn off for this site")
        }
    }
}

/// Your own CSS and JavaScript for one site.
struct SiteCodeSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var css = ""
    @State private var js = ""
    @State private var part = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Language", selection: $part) {
                    Text("CSS").tag(0)
                    Text("JavaScript").tag(1)
                }
                .pickerStyle(.segmented)

                TextEditor(text: part == 0 ? $css : $js)
                    .font(Face.mono(13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(Theme.card))
                    .overlay(alignment: .topLeading) {
                        if (part == 0 ? css : js).isEmpty {
                            Text(part == 0 ? "body { font-size: 18px; }\n.annoying-banner { display: none; }" : "document.title = 'Hello';")
                                .font(Face.mono(13))
                                .foregroundColor(Theme.muted)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }

                Text(part == 0
                     ? "Added to every page on this site. Items you hide with Hide item show up here too."
                     : "Runs after each page on this site loads. Errors are caught so the page keeps working.")
                    .font(Face.ui(12))
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(Address.display(store.current?.url))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.current?.saveCustomization(css: css, js: js)
                        Haptics.success()
                        dismiss()
                    }
                    .font(Face.ui(16, weight: .bold))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let site = store.sites.setting(for: store.current?.url)
                css = site.css
                js = site.js
            }
        }
        .modifier(SheetChrome())
    }
}
