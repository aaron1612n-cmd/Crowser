import SwiftUI

/// On-screen stick (left thumb) and two buttons (right thumb) that press keys in a web game.
struct GamePad: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(alignment: .bottom) {
            Stick(tab: tab)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 14) {
                PadButton(tab: tab, key: tab.padB, size: 64)
                PadButton(tab: tab, key: tab.padA, size: 78)
                    .padding(.bottom, 34)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
        .onDisappear { tab.releaseKeys() }
    }
}

private struct Stick: View {
    @ObservedObject var tab: BrowserTab
    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 62

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.ink.opacity(0.35))
                .overlay(Circle().stroke(Theme.onInk.opacity(0.35), lineWidth: 1.5))
            // Notches where the four directions sit.
            ForEach(0..<4) { index in
                Capsule()
                    .fill(Theme.onInk.opacity(0.4))
                    .frame(width: 3, height: 10)
                    .offset(y: -radius + 12)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle()
                .fill(Theme.ember.opacity(0.85))
                .overlay(Circle().stroke(Theme.onInk.opacity(0.5), lineWidth: 1.5))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle().inset(by: -24))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var offset = CGSize(width: value.location.x - radius, height: value.location.y - radius)
                    let length = sqrt(offset.width * offset.width + offset.height * offset.height)
                    if length > radius - 20 {
                        let scale = (radius - 20) / length
                        offset = CGSize(width: offset.width * scale, height: offset.height * scale)
                    }
                    knob = offset
                    steer(x: offset.width / (radius - 20), y: offset.height / (radius - 20))
                }
                .onEnded { _ in
                    withAnimation(Motion.snappy) { knob = .zero }
                    steer(x: 0, y: 0)
                }
        )
        .accessibilityHidden(true)
    }

    /// Diagonals hold two keys at once.
    private func steer(x: CGFloat, y: CGFloat) {
        let keys = GameKey.stick(tab.padStick)
        let wasHeld = tab.heldKeys
        tab.press(keys.up, y < -0.4)
        tab.press(keys.down, y > 0.4)
        tab.press(keys.left, x < -0.4)
        tab.press(keys.right, x > 0.4)
        if tab.heldKeys != wasHeld && !tab.heldKeys.subtracting(wasHeld).isEmpty { Haptics.select() }
    }
}

private struct PadButton: View {
    @ObservedObject var tab: BrowserTab
    let key: GameKey
    let size: CGFloat
    @State private var down = false

    var body: some View {
        Text(key.label)
            .font(Face.ui(key.label.count > 2 ? 14 : 20, weight: .heavy))
            .foregroundColor(down ? Theme.onEmber : Theme.onInk)
            .frame(width: size, height: size)
            .background(Circle().fill(down ? Theme.ember : Theme.ink.opacity(0.4)))
            .overlay(Circle().stroke(Theme.onInk.opacity(0.4), lineWidth: 1.5))
            .scaleEffect(down ? 0.92 : 1)
            .contentShape(Circle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        Haptics.tap()
                        tab.press(key, true)
                    }
                    .onEnded { _ in
                        down = false
                        tab.press(key, false)
                    }
            )
            .animation(Motion.snappy, value: down)
            .accessibilityLabel(key.label)
    }
}
