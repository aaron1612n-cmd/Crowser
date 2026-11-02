import SwiftUI

@main
struct CrowserApp: App {
    @StateObject private var library: Library
    @StateObject private var store: BrowserStore

    init() {
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
