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

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(mode?.color ?? Theme.surfaceRecede)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay {
                if let mode {
                    PipsView(count: mode.pipCount)
                        .frame(width: size * 0.58, height: size * 0.58)
                }
            }
            .frame(width: size, height: size)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}
