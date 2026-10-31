import SwiftUI

/// Serif title on the left, actions on the right, ink rule underneath. Used by every sheet.
struct SheetHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Face.display(34))
                    .foregroundColor(Rookery.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing()
            }
            .padding(.top, 26)
            .padding(.bottom, 12)
            Hairline(color: Rookery.ink)
        }
        .padding(.horizontal, 24)
    }
}

/// Mono text button in ink or ember.
struct TextAction: View {
    let title: String
    var color: Color = Rookery.ink
    let action: () -> Void

    init(_ title: String, color: Color = Rookery.ink, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.mono(14, weight: .medium))
                .foregroundColor(color)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
