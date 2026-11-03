import Foundation

/// A named, colored set of tabs.
struct TabGroup: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    /// Index into `Theme.groupTones`.
    var tone: Int
}

/// Tabs saved under a name, to reopen later.
struct SavedSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var date = Date()
    var links: [String]
}
