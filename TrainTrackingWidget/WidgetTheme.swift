import SwiftUI
import UIKit

/// Widget-target mirror of the app's Theme (the extension compiles only the
/// files in this folder, same pattern as TrainTrackingAttributes.swift).
/// The lock screen card follows the system scheme exactly like the in-app
/// journey hero: bright brand fills with dark ink in light mode, their
/// warm-ladder equivalents (stone / deep amber / dark red) with cream ink
/// in dark mode. The Dynamic Island keeps fixed colours — it always sits
/// on the system's black pill.
enum WidgetTheme {
    /// Hero backgrounds by service status (mirrors Theme.accent /
    /// heroDelayed / bad).
    static let accent = adaptive(0x5CA3B9, 0x6E6450)
    static let delayedBg = adaptive(0xF7D06B, 0x6B5210)
    static let cancelledBg = adaptive(0xE8C1B8, 0x6E3A2F)

    static let ink = adaptive(0x0E2D38, 0xF4EFE3)
    static let inkSoft = adaptive(0x2A4754, 0xD6CFBF)
    static let cream = adaptive(0xF4EFE3, 0x0E2D38)

    // Status pill colours are fixed in both schemes (mirrors the app's
    // StatusPill: the pills carry their own contrast on any hero fill).
    static let onTimeBg = Color(hex: 0xC9E265)
    static let onTimeFg = Color(hex: 0x0E2D38)
    static let delayedPillBg = Color(hex: 0x3B2A05)
    static let delayedPillFg = Color(hex: 0xF7D06B)
    static let cancelledPillBg = Color(hex: 0xA32718)
    static let cancelledPillFg = Color(hex: 0xFBEEEB)

    // Dynamic Island: fixed dark-surface colours on the black pill.
    static let islandAccent = Color(hex: 0x5CA3B9)
    static let islandDelayed = Color(hex: 0xEBAC52)
    static let islandCancelled = Color(hex: 0xEC826C)

    static func background(for status: String) -> Color {
        switch status {
        case "cancelled": return cancelledBg
        case "delayed": return delayedBg
        default: return accent
        }
    }

    private static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(widgetHex: dark)
                : UIColor(widgetHex: light)
        })
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

extension UIColor {
    convenience init(widgetHex hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
