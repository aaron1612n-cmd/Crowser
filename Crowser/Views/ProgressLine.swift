import SwiftUI

/// The one moving thing in Crowser: an ember line that runs along the edge of the bar
/// while a page loads, finishes its run, then lets go.
struct ProgressLine: View {
    let progress: Double
    let isLoading: Bool

    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Rookery.ember)
                .frame(width: geo.size.width * fraction, height: 2)
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .onChange(of: isLoading) { loading in
            if loading {
                visible = true
            } else {
                withAnimation(.easeIn(duration: 0.5).delay(0.25)) { visible = false }
            }
        }
        .onAppear { visible = isLoading }
    }

    private var fraction: CGFloat {
        guard isLoading else { return visible ? 1 : 0 }
        return CGFloat(max(progress, 0.08))
    }
}
