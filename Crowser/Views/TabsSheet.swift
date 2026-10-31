import SwiftUI

/// Open tabs as a numbered list rather than a grid of thumbnails.
struct TabsSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tabs") {
                TextAction("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            List {
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        store.select(tab)
                        dismiss()
                    } label: {
                        TabRow(index: index + 1, tab: tab, selected: tab.id == store.current?.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Rookery.paper)
                    .listRowSeparatorTint(Rookery.rule)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .swipeActions {
                        Button(role: .destructive) { store.close(tab) } label: {
                            Image(systemName: "xmark")
                        }
                        .tint(Rookery.ember)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Hairline()
            HStack(spacing: 24) {
                TextAction("+ tab") {
                    store.newTab()
                    dismiss()
                }
                TextAction("+ private", color: Rookery.ember) {
                    store.newTab(isPrivate: true)
                    dismiss()
                }
                Spacer()
                TextAction("close all", color: Rookery.ash) {
                    store.closeAll()
                    dismiss()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .background(Rookery.paper.ignoresSafeArea())
    }
}

private struct TabRow: View {
    let index: Int
    @ObservedObject var tab: BrowserTab
    let selected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(index)")
                .font(Face.display(30))
                .foregroundColor(selected ? Rookery.ember : Rookery.ash)
                .frame(minWidth: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title.isEmpty ? (tab.url == nil ? "Blank" : Address.display(tab.url)) : tab.title)
                    .font(Face.display(18))
                    .foregroundColor(Rookery.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if tab.isPrivate {
                        Image(systemName: "eye.slash").foregroundColor(Rookery.ember)
                    }
                    Text(tab.url == nil ? "—" : Address.display(tab.url))
                        .foregroundColor(Rookery.ash)
                        .lineLimit(1)
                }
                .font(Face.mono(12))
            }

            Spacer(minLength: 0)

            if selected {
                Rectangle().fill(Rookery.ember).frame(width: 3, height: 36)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
