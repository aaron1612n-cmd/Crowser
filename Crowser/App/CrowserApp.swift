import SwiftUI

@main
struct CrowserApp: App {
    @StateObject private var library: Library
    @StateObject private var store: BrowserStore

    init() {
        // A roomier shared cache keeps favicons and suggestions instant after the first load.
        URLCache.shared = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        let library = Library()
        _library = StateObject(wrappedValue: library)
        _store = StateObject(wrappedValue: BrowserStore(library: library))
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(store)
                .environmentObject(library)
                .tint(Theme.ember)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { store.newTab() }
                    .keyboardShortcut("t")
                Button("New Private Tab") { store.newTab(isPrivate: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close Tab") { store.closeCurrent() }
                    .keyboardShortcut("w")
                Button("Reopen Closed Tab") { store.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                Button("Open Location") { store.beginEditing() }
                    .keyboardShortcut("l")
                Button("Reload") { store.current?.reload() }
                    .keyboardShortcut("r")
                Button("Back") { store.current?.goBack() }
                    .keyboardShortcut("[")
                Button("Forward") { store.current?.goForward() }
                    .keyboardShortcut("]")
                Button("Add to Favorites") { store.toggleBookmarkForCurrent() }
                    .keyboardShortcut("d")
                Divider()
                Button("Show Tabs") { store.showOverview() }
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
                Button("Show Library") { store.sheet = .library }
                    .keyboardShortcut("y")
                Button("Find on Page") { store.current?.findOnPage() }
                    .keyboardShortcut("f")
                Button("Next Tab") { store.selectAdjacent(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { store.selectAdjacent(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }
}
