import SwiftUI

/// Visual language ported from the Windows app: Zinc palette, 12 px radius,
/// accent green (idle) / red (recording) / purple (processing). SF Pro + SF Mono
/// replace Segoe UI + Cascadia Code.
enum Theme {
    static let bg            = Color(hex: 0x09090B)   // zinc-950
    static let card          = Color(hex: 0x18181B)   // zinc-900
    static let cardElevated  = Color(hex: 0x1F1F23)
    static let border        = Color(hex: 0x27272A)   // zinc-800
    static let textPrimary   = Color(hex: 0xE4E4E7)   // zinc-200
    static let textMuted     = Color(hex: 0xA1A1AA)   // zinc-400
    static let textFaint     = Color(hex: 0x71717A)   // zinc-500

    static let green         = Color(hex: 0x32D583)   // idle / ready / copied
    static let red           = Color(hex: 0xFF6B6B)   // recording
    static let purple        = Color(hex: 0x8B5CF6)   // transcribing
    static let purpleAlt     = Color(hex: 0x6E56CF)
    static let orange        = Color(hex: 0xF59E0B)   // loading

    static let radius: CGFloat = 12

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
