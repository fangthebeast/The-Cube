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

// One set of semantic slots, two fillings. Every view reads colours off the
// ambient palette, so the two halves of the app are the same design in two
// different times of day — not two different designs.
struct Palette {
    let page: Color
    let paper: Color            // screen background
    let surface: Color          // cards
    let surfaceRecede: Color    // empty slots, tracks
    let ink: Color
    let inkSecondary: Color
    let inkMuted: Color
    let accent: Color           // the half's own colour: blue at night, green by day
    let accentSoft: Color
    let border: Color
    let onAccent: Color         // text on an accent fill
    let cardShadow: Color
    let glow: Color             // ambient wash behind the screen
    let glowOpacity: Double
    let isDark: Bool

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

extension Palette {
    // Night. Darker than the old single theme, and the accent is the party
    // blue — the room lights are off and the cube is the brightest thing in it.
    static let night = Palette(
        page: Color(hex: 0x050907),
        paper: Color(hex: 0x0A1210),
        surface: Color(hex: 0x141F1B),
        surfaceRecede: Color(hex: 0x1E2B26),
        ink: Color(hex: 0xF3F1E7),
        inkSecondary: Color(hex: 0xA8B0A6),
        inkMuted: Color(hex: 0x75817A),
        accent: Color(hex: 0x3987E5),
        accentSoft: Color(hex: 0x14243A),
        border: Color(hex: 0xF3F1E7).opacity(0.10),
        onAccent: Color(hex: 0x050907),
        cardShadow: .clear,
        glow: Color(hex: 0x3987E5),
        glowOpacity: 0.20,
        isDark: true
    )

    // Morning. The mockup's paper feel, right way up: warm off-white stock,
    // near-black ink, the recovery green as the accent.
    static let day = Palette(
        page: Color(hex: 0xEBE7D8),
        paper: Color(hex: 0xF6F3E9),
        surface: Color(hex: 0xFFFDF6),
        surfaceRecede: Color(hex: 0xE4E0D0),
        ink: Color(hex: 0x16211B),
        inkSecondary: Color(hex: 0x53615A),
        inkMuted: Color(hex: 0x8B968E),
        accent: Color(hex: 0x199E70),
        accentSoft: Color(hex: 0xDCEDE3),
        border: Color(hex: 0x16211B).opacity(0.10),
        onAccent: Color(hex: 0xFCFFFD),
        cardShadow: Color(hex: 0x16211B).opacity(0.07),
        glow: Color(hex: 0xF2C75B),
        glowOpacity: 0.22,
        isDark: false
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .night
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// Colours that mean the same thing in both halves and never change with the
// palette: the party blue, and the traffic light the debt bar runs on.
enum Theme {
    static let party = Color(hex: 0x3987E5)
    static let debtRed = Color(hex: 0xD95926)
    static let debtYellow = Color(hex: 0xC98500)
    static let debtGreen = Color(hex: 0x199E70)
    static let neutral = Color(hex: 0x8B968E)
}

// A soft off-centre wash — the only decoration either theme gets. Blue in a
// dark room at night, low sun in the morning.
struct AmbientGlow: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [palette.glow.opacity(palette.glowOpacity), .clear],
                center: .init(x: 0.5, y: 0.08),
                startRadius: 0,
                endRadius: geo.size.width * 0.95
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
