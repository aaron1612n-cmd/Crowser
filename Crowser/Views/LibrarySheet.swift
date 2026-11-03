import SwiftUI
import UniformTypeIdentifiers

/// Favorites and history, searchable, with swipe-to-delete.
struct LibrarySheet: View {
    enum Shelf: String, CaseIterable { case favorites = "Favorites", history = "History" }

    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var shelf: Shelf = .favorites
    @State private var filter = ""
    @State private var importing = false

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
                                .contextMenu {
                                    if shelf == .favorites { folderMenu(for: entry) }
                                }
                            }
                        } header: {
                            if !section.title.isEmpty {
                                HStack {
                                    if shelf == .favorites && section.title != "Not in a folder" {
                                        Image(systemName: "folder.fill").foregroundColor(Theme.ember)
                                    }
                                    Text(section.title)
                                        .font(Face.ui(13, weight: .bold))
                                        .foregroundColor(Theme.muted)
                                        .textCase(nil)
                                    Spacer()
                                    if shelf == .favorites && section.title != "Not in a folder" {
                                        Menu {
                                            Button { rename(section.title) } label: { Label("Rename", systemImage: "pencil") }
                                            Button(role: .destructive) { library.deleteFolder(section.title) } label: {
                                                Label("Remove Folder", systemImage: "folder.badge.minus")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle").foregroundColor(Theme.muted)
                                        }
                                        .accessibilityLabel("Folder options")
                                    }
                                }
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
                if shelf == .favorites {
                    ToolbarItem(placement: .cancellationAction) {
                        Menu {
                            Button {
                                Task {
                                    if let name = await Presenter.prompt(title: "New folder", message: "Name it, like Games or School", defaultText: nil) {
                                        library.createFolder(name)
                                    }
                                }
                            } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                            Button { importing = true } label: {
                                Label("Import from Safari, Chrome…", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("Folders and import")
                    }
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.html, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            let count = library.importBookmarks(html: html)
            Haptics.success()
            store.showToast(count == 0 ? "Nothing new to import" : "Imported \(count) favorite\(count == 1 ? "" : "s")")
        }
        .modifier(SheetChrome())
    }

    @ViewBuilder
    private func folderMenu(for entry: Entry) -> some View {
        Menu {
            Button { library.move(entry.url, toFolder: nil) } label: {
                Label("Not in a folder", systemImage: entry.folder == nil ? "checkmark" : "tray")
            }
            ForEach(library.folders, id: \.self) { folder in
                Button { library.move(entry.url, toFolder: folder) } label: {
                    Label(folder, systemImage: entry.folder == folder ? "checkmark" : "folder")
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
    }

    private func rename(_ folder: String) {
        Task {
            if let name = await Presenter.prompt(title: "Rename folder", message: "", defaultText: folder) {
                library.renameFolder(folder, to: name)
            }
        }
    }

    private struct Bucket { let title: String; let entries: [Entry] }

    /// History is grouped by day; favorites are one list.
    private var sections: [Bucket] {
        guard shelf == .history else {
            let loose = entries.filter { $0.folder == nil }
            var buckets: [Bucket] = []
            if !loose.isEmpty { buckets.append(Bucket(title: library.folders.isEmpty ? "" : "Not in a folder", entries: loose)) }
            for folder in library.folders {
                let inside = entries.filter { $0.folder == folder }
                if !inside.isEmpty || filter.isEmpty { buckets.append(Bucket(title: folder, entries: inside)) }
            }
            return buckets
        }
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
