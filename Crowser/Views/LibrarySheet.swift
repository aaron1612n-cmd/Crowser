import SwiftUI

/// Favorites and history, searchable, with swipe-to-delete.
struct LibrarySheet: View {
    enum Shelf: String, CaseIterable { case favorites = "Favorites", history = "History" }

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf = .favorites
    @State private var filter = ""

    private var entries: [Entry] {
        let all = shelf == .favorites ? library.bookmarks : library.history
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(needle) || $0.url.absoluteString.lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $shelf.animation(Motion.snappy)) {
                        ForEach(Shelf.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if entries.isEmpty {
                    Section {
                        Text(filter.isEmpty ? (shelf == .favorites ? "No favorites yet. Tap ☆ in the … menu on any page." : "Nothing here yet.") : "No matches.")
                            .font(Face.ui(15))
                            .foregroundColor(Theme.muted)
                            .listRowBackground(Theme.card)
                    }
                } else {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                EntryRow(entry: entry) {
                                    store.open(entry.url)
                                    dismiss()
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Theme.card)
                                .listRowSeparator(.hidden)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        withAnimation { remove(entry) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            if !section.title.isEmpty {
                                Text(section.title)
                                    .font(Face.ui(13, weight: .bold))
                                    .foregroundColor(Theme.muted)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .searchable(text: $filter, prompt: "Search \(shelf.rawValue.lowercased())")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Face.ui(16, weight: .bold))
                }
                if shelf == .history && !library.history.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Menu("Clear") {
                            Button("Clear all history", role: .destructive) { library.clearHistory() }
                        }
                    }
                }
            }
        }
        .modifier(SheetChrome())
    }

    private struct Bucket { let title: String; let entries: [Entry] }

    /// History is grouped by day; favorites are one list.
    private var sections: [Bucket] {
        guard shelf == .history else { return [Bucket(title: "", entries: entries)] }
        let calendar = Calendar.current
        var groups: [Bucket] = []
        for entry in entries {
            let title: String
            if calendar.isDateInToday(entry.date) {
                title = "Today"
            } else if calendar.isDateInYesterday(entry.date) {
                title = "Yesterday"
            } else {
                title = entry.date.formatted(.dateTime.weekday(.wide).month().day())
            }
            if groups.last?.title == title {
                groups[groups.count - 1] = Bucket(title: title, entries: groups[groups.count - 1].entries + [entry])
            } else {
                groups.append(Bucket(title: title, entries: [entry]))
            }
        }
        return groups
    }

    private func remove(_ entry: Entry) {
        switch shelf {
        case .favorites: library.removeBookmark(entry.url)
        case .history: library.removeHistory(entry.id)
        }
    }
}
