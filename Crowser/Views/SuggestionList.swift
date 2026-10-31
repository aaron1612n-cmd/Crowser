import SwiftUI

/// Shown over the page while typing in the address bar.
struct SuggestionList: View {
    let query: String

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library

    var body: some View {
        let matches = library.suggestions(for: query)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !trimmed.isEmpty {
                    Button { store.open(trimmed) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Rookery.ember)
                                .frame(width: 22, alignment: .leading)
                            Text(trimmed)
                                .font(Face.mono(15))
                                .foregroundColor(Rookery.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            SmallCaps(Address.resolve(trimmed)?.host == nil ? "" : "go")
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Hairline()
                }

                ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                    Button { store.open(entry.url) } label: {
                        EntryRow(index: index + 1, entry: entry)
                    }
                    .buttonStyle(RowPressStyle())
                    Hairline()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Rookery.paper)
    }
}
