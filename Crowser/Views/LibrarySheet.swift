import SwiftUI

struct LibrarySheet: View {
    enum Shelf: String, CaseIterable { case roost = "Roost", lately = "Lately" }

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf = .roost

    private var entries: [Entry] { shelf == .roost ? library.bookmarks : library.history }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Library") {
                TextAction("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 28) {
                ForEach(Shelf.allCases, id: \.self) { item in
                    Button { shelf = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            SmallCaps(item.rawValue, color: shelf == item ? Rookery.ink : Rookery.ash)
                            Rectangle()
                                .fill(shelf == item ? Rookery.ember : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(shelf == item ? .isSelected : [])
                }
                Spacer()
                if shelf == .lately && !library.history.isEmpty {
                    TextAction("clear", color: Rookery.ash) { library.clearHistory() }
                }
            }
            .padding(.horizontal, 24)

            if entries.isEmpty {
                Text(shelf == .roost ? "nothing perched yet" : "nowhere yet")
                    .font(Face.display(17).italic())
                    .foregroundColor(Rookery.ash)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                Spacer()
            } else {
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            store.open(entry.url)
                            dismiss()
                        } label: {
                            EntryRow(index: index + 1, entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Rookery.paper)
                        .listRowSeparatorTint(Rookery.rule)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    }
                    .onDelete { offsets in
                        shelf == .roost ? library.removeBookmarks(at: offsets) : library.removeHistory(at: offsets)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Rookery.paper.ignoresSafeArea())
    }
}
