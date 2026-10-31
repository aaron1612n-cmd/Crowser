import SwiftUI
import UIKit

/// "Rookery": a crow's palette. Soot and bone do the work; ember is the only accent.
enum Rookery {
    static let soot = Color(uiColor: .rookery(0x15130F))
    static let feather = Color(uiColor: .rookery(0x2A2722))
    static let bone = Color(uiColor: .rookery(0xEEE7D7))
    static let ash = Color(uiColor: .rookery(0x8A8476))
    static let ember = Color(uiColor: .rookery(0xD9481C))

    /// Page ground: bone by day, soot by night.
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .rookery(0x15130F) : .rookery(0xEEE7D7) })
    /// Text on paper.
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .rookery(0xEEE7D7) : .rookery(0x15130F) })
    /// Hairlines on paper.
    static let rule = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .rookery(0xEEE7D7, alpha: 0.14) : .rookery(0x15130F, alpha: 0.16)
    })
}

extension UIColor {
    static func rookery(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Type pairing: New York (serif) for names and numbers, SF Mono for addresses and labels.
enum Face {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Small uppercase mono label used for section heads.
struct SmallCaps: View {
    let text: String
    var color: Color = Rookery.ash

    init(_ text: String, color: Color = Rookery.ash) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Face.mono(11, weight: .medium))
            .tracking(1.6)
            .foregroundColor(color)
    }
}

/// A one-point rule in the current ink.
struct Hairline: View {
    var color: Color = Rookery.rule
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}
