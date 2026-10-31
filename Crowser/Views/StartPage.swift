import SwiftUI

/// What a blank tab shows: the wordmark, the roost (bookmarks) and what you read lately.
struct StartPage: View {
    let isPrivate: Bool

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.horizontalSizeClass) private var horizontalSize

    private var wide: Bool { horizontalSize == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.bottom, wide ? 56 : 36)

                if wide {
                    HStack(alignment: .top, spacing: 48) {
                        roost.frame(maxWidth: .infinity, alignment: .topLeading)
                        lately.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 40) {
                        roost
                        lately
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, wide ? 56 : 24)
            .padding(.top, wide ? 64 : 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Rookery.paper)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallCaps(Self.dateLine.string(from: Date()))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Crowser")
                    .font(Face.display(wide ? 84 : 58))
                    .foregroundColor(Rookery.ink)
                Text(".")
                    .font(Face.display(wide ? 84 : 58))
                    .foregroundColor(Rookery.ember)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if isPrivate {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                    Text("private — nothing is kept")
                }
                .font(Face.mono(13))
                .foregroundColor(Rookery.ember)
                .padding(.top, 4)
            }
        }
    }

    private var roost: some View {
        Shelf(
            title: "Roost",
            entries: Array(library.bookmarks.prefix(wide ? 10 : 6)),
            empty: "nothing perched yet"
        ) { store.open($0.url) }
    }

    private var lately: some View {
        Shelf(
            title: "Lately",
            entries: isPrivate ? [] : library.recent(wide ? 10 : 5),
            empty: isPrivate ? "not recorded here" : "nowhere yet"
        ) { store.open($0.url) }
    }

    private static let dateLine: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}

/// A titled, numbered, ruled list of links.
private struct Shelf: View {
    let title: String
    let entries: [Entry]
    let empty: String
    let open: (Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SmallCaps(title, color: Rookery.ink)
                Spacer()
                if !entries.isEmpty { SmallCaps(String(format: "%02d", entries.count)) }
            }
            .padding(.bottom, 10)
            Hairline(color: Rookery.ink)

            if entries.isEmpty {
                Text(empty)
                    .font(Face.display(17).italic())
                    .foregroundColor(Rookery.ash)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { open(entry) } label: {
                        EntryRow(index: index + 1, entry: entry)
                    }
                    .buttonStyle(RowPressStyle())
                    Hairline()
                }
            }
        }
    }
}

struct EntryRow: View {
    let index: Int
    let entry: Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(String(format: "%02d", index))
                .font(Face.mono(12))
                .foregroundColor(Rookery.ash)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(Face.display(18))
                    .foregroundColor(Rookery.ink)
                    .lineLimit(1)
                Text(Address.display(entry.url))
                    .font(Face.mono(12))
                    .foregroundColor(Rookery.ash)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Rows darken slightly under a finger instead of flashing a system highlight.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Rookery.rule : Color.clear)
    }
}
