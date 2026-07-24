import SwiftUI

/// Widget-target mirror of the app's Theme (the extension compiles only the
/// files in this folder, same pattern as TrainTrackingAttributes.swift).
/// Values are FIXED, not adaptive: the lock screen card paints the app's
/// hero look — bright status background with dark ink text — which must
/// stay identical in dark mode, exactly like the in-app hero forces light.
enum WidgetTheme {
    /// Hero backgrounds by service status (JourneyScreen.heroBg).
    static let accent = Color(hex: 0x5CA3B9)
    static let warn = Color(hex: 0xF7D06B)
    static let bad = Color(hex: 0xE8C1B8)

    static let ink = Color(hex: 0x0E2D38)
    static let inkSoft = Color(hex: 0x2A4754)
    static let cream = Color(hex: 0xF4EFE3)

    // Status pill colours (Theme.onTimeBg / trackPill*).
    static let onTimeBg = Color(hex: 0xC9E265)
    static let delayedPillBg = Color(hex: 0x3B2A05)
    static let delayedPillFg = Color(hex: 0xF7D06B)
    static let cancelledPillBg = Color(hex: 0xA32718)
    static let cancelledPillFg = Color(hex: 0xFBEEEB)

    // Dynamic Island sits on the system's black pill — status colours there
    // need dark-surface contrast (Theme's dark-mode delayed/cancelled text).
    static let islandDelayed = Color(hex: 0xEBAC52)
    static let islandCancelled = Color(hex: 0xEC826C)

    static func background(for status: String) -> Color {
        switch status {
        case "cancelled": return bad
        case "delayed": return warn
        default: return accent
        }
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
