import AVFoundation
import SwiftUI

@main
struct CrowserApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library: Library
    @StateObject private var store: BrowserStore

    init() {
        // A roomier shared cache keeps favicons and suggestions instant after the first load.
        URLCache.shared = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        // Lets videos and music from web pages keep playing with the screen off or in another app,
        // and lets picture in picture float over other apps.
        if UserDefaults.standard.object(forKey: "crowser.pref.backgroundAudio") as? Bool ?? true {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }
        let library = Library()
        _library = StateObject(wrappedValue: library)
        _store = StateObject(wrappedValue: BrowserStore(library: library))
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(store)
                .environmentObject(library)
                .environmentObject(Prefs.shared)
                .environmentObject(store.sites)
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
                Button("Reload Without Cache") { store.current?.hardReload() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Reader View") { store.current?.toggleReader() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Scroll to Top") { store.current?.scrollToTop() }
                    .keyboardShortcut(.upArrow)
                Button("Scroll to Bottom") { store.current?.scrollToBottom() }
                    .keyboardShortcut(.downArrow)
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
                Button("Command Palette") { store.sheet = .palette }
                    .keyboardShortcut("k")
                Button("Show or Hide Toolbar") { store.toggleTuck() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Shields") { store.sheet = .shields }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Settings") { store.sheet = .settings }
                    .keyboardShortcut(",")
                Button("Pin Tab") { if let tab = store.current { store.togglePin(tab) } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Duplicate Tab") { if let tab = store.current { store.duplicate(tab) } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Zoom In") { store.current?.stepZoom(1) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { store.current?.stepZoom(-1) }
                    .keyboardShortcut("-")
                Button("Actual Size") { store.current?.resetZoom() }
                    .keyboardShortcut("0")
                Button("Next Tab") { store.selectAdjacent(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { store.selectAdjacent(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }
}
