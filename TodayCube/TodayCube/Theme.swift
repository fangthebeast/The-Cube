import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// Hardcoded dark palette from the mockup — the app has no light theme.
enum Theme {
    static let page = Color(hex: 0x0A0E0B)
    static let paper = Color(hex: 0x14201B)
    static let surface = Color(hex: 0x1C2A23)
    static let surfaceRecede = Color(hex: 0x22302A)
    static let ink = Color(hex: 0xF3F1E7)
    static let inkSecondary = Color(hex: 0xA8B0A6)
    static let inkMuted = Color(hex: 0x75817A)
    static let accent = Color(hex: 0x6FBFA0)
    static let accentSoft = Color(hex: 0x24352C)
    static let border = Color(hex: 0xF3F1E7).opacity(0.10)
}
