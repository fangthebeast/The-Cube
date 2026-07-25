import SwiftUI

// Die-face pip layout on a 3x3 grid, cells numbered 1–9 row-major.
struct PipsView: View {
    let count: Int
    var color: Color = .white.opacity(0.95)

    private static let layouts: [Int: [Int]] = [
        1: [5],
        2: [1, 9],
        3: [1, 5, 9],
        4: [1, 3, 7, 9],
        5: [1, 3, 5, 7, 9],
        6: [1, 3, 4, 6, 7, 9],
    ]

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let pip = s * 0.21
            ZStack(alignment: .topLeading) {
                ForEach(Self.layouts[count] ?? [], id: \.self) { cell in
                    let row = (cell - 1) / 3
                    let col = (cell - 1) % 3
                    Circle()
                        .fill(color)
                        .frame(width: pip, height: pip)
                        .position(
                            x: s * (0.22 + 0.28 * CGFloat(col)),
                            y: s * (0.22 + 0.28 * CGFloat(row))
                        )
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct DieFaceView: View {
    let mode: Mode?
    var size: CGFloat = 58
    var pipColorOverride: Color?

    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(mode?.color ?? palette.surfaceRecede)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay {
                if let mode {
                    PipsView(count: mode.pipCount, color: pipColorOverride ?? .white.opacity(0.95))
                        .frame(width: size * 0.58, height: size * 0.58)
                }
            }
            .frame(width: size, height: size)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 24
    var fill: Color?

    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill ?? palette.surface)
                    // Invisible at night; on paper it's what lifts a card off
                    // the page now that the background is lighter than it is.
                    .shadow(color: palette.cardShadow, radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(cornerRadius: CGFloat = 24, fill: Color? = nil) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, fill: fill))
    }
}

// Screen header. Triple-tapping the title opens the dev panel — the demo
// never depends on live BLE working in the room.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var accent: Color?

    @Environment(\.palette) private var palette
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(accent ?? palette.inkMuted)
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 3) { ui.showDevPanel = true }
        // Long-press does the same thing — triple-tapping on a table mid-demo
        // is easy to fumble.
        .onLongPressGesture(minimumDuration: 0.8) { ui.showDevPanel = true }
    }
}

struct BigButton: View {
    let title: String
    var tint: Color?
    var filled: Bool = true
    let action: () -> Void

    @Environment(\.palette) private var palette

    private var color: Color { tint ?? palette.accent }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(filled ? palette.onAccent : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(filled ? color : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(filled ? Color.clear : color.opacity(0.5), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var valueColor: Color?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .monospaced))
                .foregroundStyle(valueColor ?? palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 16)
    }
}

struct ConnectionDot: View {
    let connected: Bool
    let label: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? palette.accent : palette.inkMuted)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(palette.inkMuted)
        }
    }
}

enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension TimeInterval {
    // "1h 24m" / "6m" — used for session length and activity timers.
    var compactDuration: String {
        let total = Int(max(0, self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
