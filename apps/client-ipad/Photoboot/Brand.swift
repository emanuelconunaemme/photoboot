import SwiftUI

// Instagram-inspired brand palette + gradient. Use `Brand.gradient` on primary
// CTAs and the capture button; everything else inherits the AccentColor (IG pink).
enum Brand {
    static let purple = Color(red: 0.514, green: 0.227, blue: 0.706)  // #833AB4
    static let pink   = Color(red: 0.882, green: 0.188, blue: 0.424)  // #E1306C
    static let red    = Color(red: 0.992, green: 0.114, blue: 0.114)  // #FD1D1D
    static let orange = Color(red: 0.988, green: 0.690, blue: 0.271)  // #FCB045
    static let yellow = Color(red: 1.000, green: 0.863, blue: 0.502)  // #FFDC80

    static let gradient = LinearGradient(
        colors: [purple, pink, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gradient built from an event's primary + secondary colors.
    /// Used on the capture button ring so the button that "starts the
    /// countdown" carries the event's identity. Everything else stays IG.
    static func eventGradient(for event: Event) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: event.primaryColor), Color(hex: event.secondaryColor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func eventPrimary(for event: Event) -> Color {
        Color(hex: event.primaryColor)
    }

    static func eventSecondary(for event: Event) -> Color {
        Color(hex: event.secondaryColor)
    }
}

extension Color {
    /// Parses "#RRGGBB" (or "RRGGBB"). Falls back to `.gray` if unparseable.
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
