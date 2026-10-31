import SwiftUI
import WebKit

struct SettingsSheet: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SearchEngine.storageKey) private var engine: SearchEngine = .duckDuckGo
    @State private var clearedData = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settings") {
                TextAction("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    section("Search with") {
                        ForEach(SearchEngine.allCases) { option in
                            Button { engine = option } label: {
                                HStack {
                                    Text(option.name)
                                        .font(Face.display(19))
                                        .foregroundColor(Rookery.ink)
                                    Spacer()
                                    Circle()
                                        .fill(engine == option ? Rookery.ember : .clear)
                                        .overlay(Circle().stroke(engine == option ? Rookery.ember : Rookery.ash, lineWidth: 1.5))
                                        .frame(width: 12, height: 12)
                                }
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityAddTraits(engine == option ? .isSelected : [])
                            Hairline()
                        }
                    }

                    section("Forget") {
                        row("History", detail: "\(library.history.count) pages") {
                            library.clearHistory()
                        }
                        Hairline()
                        row("Cookies & site data", detail: clearedData ? "cleared" : "all sites") {
                            WKWebsiteDataStore.default().removeData(
                                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                modifiedSince: .distantPast
                            ) {
                                clearedData = true
                            }
                        }
                        Hairline()
                    }

                    SmallCaps("Crowser \(version)")
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Rookery.paper.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallCaps(title, color: Rookery.ink)
                .padding(.bottom, 8)
            Hairline(color: Rookery.ink)
            content()
        }
    }

    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Face.display(19))
                    .foregroundColor(Rookery.ink)
                Spacer()
                Text(detail)
                    .font(Face.mono(12))
                    .foregroundColor(Rookery.ash)
                Text("clear")
                    .font(Face.mono(13, weight: .medium))
                    .foregroundColor(Rookery.ember)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}
