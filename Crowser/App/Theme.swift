import SwiftUI
import UIKit

/// Crowser's palette. Warm paper, crow-black ink for the floating bar, and one accent: ember.
enum Theme {
    // Ink: the bar and anything that sits on it.
    static let ink = Color(uiColor: .hex(0x171614))
    static let inkRaised = Color(uiColor: .hex(0x2A2825))
    static let onInk = Color(uiColor: .hex(0xF3EFE7))
    static let onInkMuted = Color(uiColor: .hex(0x9A9488))

    /// The one accent. Ember by default; Settings → Look can swap it for another preset.
    static var ember: Color { Color(uiColor: .hex(Look.accent.hex)) }
    /// Text and icons placed on the accent.
    static var onEmber: Color { Color(uiColor: .hex(Look.accent.onAccent)) }
    static var emberUI: UIColor { .hex(Look.accent.hex) }

    /// Corner radius scaled by the roundness setting.
    static func r(_ base: CGFloat) -> CGFloat { base * Look.roundness }

    /// The floating bar: crow-black on light pages, lifted to charcoal at night so it never vanishes.
    static let bar = adaptive(light: 0x171614, dark: 0x2B2926)
    static let barRaised = adaptive(light: 0x2C2A27, dark: 0x3C3935)
    static let barEdge = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .hex(0xFFFFFF, alpha: 0.10) : .hex(0xFFFFFF, alpha: 0.0)
    })

    /// Page ground.
    static let paper = adaptive(light: 0xF4F0E8, dark: 0x100F0E)
    /// Raised surfaces on paper: rows, tiles, cards.
    static let card = adaptive(light: 0xFFFDF9, dark: 0x1D1B19)
    /// Primary text on paper.
    static let text = adaptive(light: 0x1A1916, dark: 0xF1EDE5)
    /// Secondary text on paper (darker with high contrast on).
    static var muted: Color { Look.highContrast ? text : mutedSoft }
    private static let mutedSoft = adaptive(light: 0x7F796E, dark: 0x8F897E)
    /// Hairlines on paper.
    static let line = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .hex(0xFFFFFF, alpha: 0.09) : .hex(0x000000, alpha: 0.08)
    })

    /// Muted earth tones for letter tiles when a site has no icon.
    static let tileTones: [Color] = ([0x8C4A2F, 0x5D6A4C, 0x4C5966, 0x8A6D3B, 0x6A4C5D, 0x3F5F5A] as [UInt32]).map { Color(uiColor: .hex($0)) }

    static let paperUI = UIColor { $0.userInterfaceStyle == .dark ? .hex(0x100F0E) : .hex(0xF4F0E8) }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .hex(dark) : .hex(light) })
    }
}

extension UIColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Type pairing: New York (serif) for titles, SF Rounded for everything you touch.
enum Face {
    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size * Look.textScale, weight: heavier(weight), design: .serif)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * Look.textScale, weight: heavier(weight), design: .rounded)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size * Look.textScale, weight: Look.boldText ? .semibold : .regular, design: .monospaced)
    }

    private static func heavier(_ weight: Font.Weight) -> Font.Weight {
        guard Look.boldText else { return weight }
        switch weight {
        case .ultraLight, .thin, .light: return .regular
        case .regular: return .semibold
        case .medium: return .bold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return .black
        }
    }
}

/// One set of springs so every movement in the app feels like the same material.
enum Motion {
    static var snappy: Animation { Look.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.84) }
    static var soft: Animation { Look.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.48, dampingFraction: 0.86) }
    static var quick: Animation { .easeOut(duration: Look.reduceMotion ? 0.1 : 0.18) }
}

enum Haptics {
    static func tap() {
        guard Look.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func thud() {
        guard Look.haptics else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func select() {
        guard Look.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard Look.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Buttons that dip slightly under a finger.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Scroll views only bounce when there is something to scroll.
struct CalmScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

extension View {
    func calmScroll() -> some View { modifier(CalmScroll()) }
}

/// Section title used on the start page and in sheets.
struct SectionTitle: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Face.title(22))
                .foregroundColor(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Face.ui(13, weight: .medium))
                    .foregroundColor(Theme.muted)
            }
        }
    }
}
