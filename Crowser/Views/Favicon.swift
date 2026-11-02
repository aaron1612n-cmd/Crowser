import SwiftUI

/// A site's icon, or a lettered tile in an earthy tone when the site has none.
struct Favicon: View {
    let url: URL?
    let title: String
    var size: CGFloat = 28

    private var host: String { Address.display(url) }

    private var iconURL: URL? {
        guard !host.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: size > 32 ? "128" : "64"),
        ]
        return components?.url
    }

    var body: some View {
        AsyncImage(url: iconURL, transaction: Transaction(animation: Motion.quick)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.16)
                    .frame(width: size, height: size)
                    .background(Color.white)
            default:
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        let letter = (title.first ?? host.first).map { String($0).uppercased() } ?? "•"
        let seed = host.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let tone = Theme.tileTones[seed % Theme.tileTones.count]
        return Text(letter)
            .font(Face.title(size * 0.5))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(tone)
    }
}

/// Favorites as a grid of icon tiles with short names.
struct FavoritesGrid: View {
    let entries: [Entry]
    var compact = false
    let open: (Entry) -> Void

    @EnvironmentObject private var library: Library

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 70 : 78, maximum: 100), spacing: 10, alignment: .top)], spacing: 16) {
            ForEach(entries) { entry in
                Button {
                    Haptics.tap()
                    open(entry)
                } label: {
                    VStack(spacing: 7) {
                        Favicon(url: entry.url, title: entry.title, size: compact ? 52 : 60)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                        Text(entry.title)
                            .font(Face.ui(12, weight: .medium))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(Motion.snappy) { library.removeBookmark(entry.url) }
                    } label: {
                        Label("Remove from Favorites", systemImage: "star.slash")
                    }
                }
            }
        }
    }
}
