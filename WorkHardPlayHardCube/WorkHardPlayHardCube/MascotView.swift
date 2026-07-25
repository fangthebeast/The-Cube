import SwiftUI

// The cube as a character. Expression is driven by the debt band — the cube
// is the one who's rough, never the person looking at it.
struct MascotView: View {
    let band: DebtBand
    var size: CGFloat = 150

    @State private var bobbing = false
    @State private var poke: CGFloat = 1

    private static let design: CGFloat = 140

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.design * 0.26, style: .continuous)
                .fill(band.color)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.design * 0.26, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: band.color.opacity(0.35), radius: 22, y: 10)

            face
        }
        .frame(width: Self.design, height: Self.design)
        .scaleEffect(size / Self.design)
        .frame(width: size, height: size)
        .scaleEffect(poke)
        .offset(y: bobbing ? -5 : 0)
        .animation(.easeInOut(duration: band == .red ? 2.6 : 1.6).repeatForever(autoreverses: true),
                   value: bobbing)
        .onAppear { bobbing = true }
        .onTapGesture {
            withAnimation(.spring(duration: 0.22)) { poke = 1.07 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(duration: 0.3)) { poke = 1 }
            }
        }
    }

    // Fixed dark, not the palette's page colour: the face is drawn on the
    // saturated body, which is the same colour in both themes.
    private var ink: Color { Color(hex: 0x0B120E).opacity(0.85) }

    @ViewBuilder
    private var face: some View {
        switch band {
        case .red:
            ZStack {
                CrossEye().stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .position(x: 50, y: 58)
                CrossEye().stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .position(x: 90, y: 58)
                WavyMouth().stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 46, height: 14)
                    .position(x: 70, y: 92)
            }
            .frame(width: Self.design, height: Self.design)

        case .yellow:
            ZStack {
                Capsule().fill(ink).frame(width: 15, height: 4).position(x: 50, y: 60)
                Capsule().fill(ink).frame(width: 15, height: 4).position(x: 90, y: 60)
                SmileMouth(curve: -3).stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 40, height: 16)
                    .position(x: 70, y: 92)
            }
            .frame(width: Self.design, height: Self.design)

        case .green:
            ZStack {
                SmileMouth(curve: -9).stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 20, height: 12)
                    .position(x: 50, y: 60)
                SmileMouth(curve: -9).stroke(ink, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: 20, height: 12)
                    .position(x: 90, y: 60)
                SmileMouth(curve: 14).stroke(ink, style: .init(lineWidth: 4.5, lineCap: .round))
                    .frame(width: 48, height: 20)
                    .position(x: 70, y: 88)
            }
            .frame(width: Self.design, height: Self.design)
        }
    }
}

struct CrossEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

struct SmileMouth: Shape {
    var curve: CGFloat        // positive = smile, negative = frown/arch

    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.midY + curve * 2))
        return p
    }
}

struct WavyMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = rect.width / 4
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for i in 0..<4 {
            let x = rect.minX + step * CGFloat(i + 1)
            let control = CGPoint(x: x - step / 2,
                                  y: rect.midY + (i % 2 == 0 ? -rect.height / 2 : rect.height / 2))
            p.addQuadCurve(to: CGPoint(x: x, y: rect.midY), control: control)
        }
        return p
    }
}

// One-shot confetti for the moment the debt hits zero.
struct ConfettiView: View {
    let colors: [Color] = [
        Color(hex: 0x199E70), Color(hex: 0x6FBFA0), Color(hex: 0xC98500),
        Color(hex: 0x3987E5), Color(hex: 0xD55181),
    ]

    @State private var launched = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<44, id: \.self) { i in
                    let x = CGFloat.random(in: 0...geo.size.width)
                    let delay = Double.random(in: 0...0.5)
                    let spin = Double.random(in: -540...540)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colors[i % colors.count])
                        .frame(width: CGFloat.random(in: 5...9), height: CGFloat.random(in: 9...15))
                        .position(x: x, y: launched ? geo.size.height + 40 : -30)
                        .rotationEffect(.degrees(launched ? spin : 0))
                        .opacity(launched ? 0.0 : 1)
                        .animation(.easeIn(duration: Double.random(in: 1.6...2.6)).delay(delay),
                                   value: launched)
                }
            }
            .onAppear { launched = true }
        }
        .allowsHitTesting(false)
    }
}
