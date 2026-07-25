import SwiftUI

struct PipView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPANION")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(Theme.inkMuted)
                    Text("Pip.")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                companionCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.paper)
    }

    private var companionCard: some View {
        VStack(spacing: 10) {
            Text(store.pipStageLabel)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)

            CreatureView(
                happy: store.todayLogged,
                stage: store.pipStage,
                unlocked: Mode.allCases.filter { store.unlockedModes.contains($0) }
            )
            .frame(width: 190, height: 176)

            Text("Pip")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)

            // Exactly two moods, driven only by whether today is logged.
            Text(store.todayLogged ? "Feeling happy" : "Feeling content")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)

            accessoryChips

            Text("Log a mode 3 times and its accessory joins Pip for good.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 26)
    }

    private var accessoryChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { mode in
                let unlocked = store.unlockedModes.contains(mode)
                HStack(spacing: 5) {
                    Circle()
                        .fill(unlocked ? mode.color : Color.clear)
                        .frame(width: 7, height: 7)
                    Text(mode.accessoryName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(unlocked ? Theme.accent : Theme.inkMuted)
                .background(
                    Capsule().fill(unlocked ? Theme.accentSoft : Color.clear)
                )
                .overlay {
                    if !unlocked {
                        Capsule().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .opacity(unlocked ? 1 : 0.5)
            }
        }
        .padding(.top, 2)
    }
}

// Pip: a rounded blob with two eyes and a mouth, drawn from the mockup's SVG
// paths in a 140x130 design space. Accessory dots orbit the body, one per
// unlocked mode — purely additive, never removed.
struct CreatureView: View {
    let happy: Bool
    let stage: Int
    let unlocked: [Mode]

    @State private var bobbing = false
    @State private var petBounce = false

    private static let designSize = CGSize(width: 140, height: 130)
    private static let accessoryPositions: [CGPoint] = [
        CGPoint(x: 22, y: 30), CGPoint(x: 118, y: 28), CGPoint(x: 14, y: 78),
        CGPoint(x: 126, y: 80), CGPoint(x: 34, y: 108), CGPoint(x: 106, y: 110),
    ]

    private var stageScale: CGFloat {
        stage == 1 ? 0.82 : stage == 2 ? 1.0 : 1.12
    }

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / Self.designSize.width,
                          geo.size.height / Self.designSize.height)
            ZStack(alignment: .topLeading) {
                creatureBody
                    .scaleEffect(stageScale, anchor: .center)
                accessoryDots
            }
            .frame(width: Self.designSize.width, height: Self.designSize.height)
            .scaleEffect(fit)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .scaleEffect(petBounce ? 1.08 : 1.0)
        .offset(y: bobbing ? -6 : 0)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bobbing)
        .onAppear { bobbing = true }
        .onTapGesture {
            // A little bounce, nothing more — petting has no reward loop.
            withAnimation(.spring(duration: 0.25)) { petBounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(duration: 0.3)) { petBounce = false }
            }
        }
    }

    private var creatureBody: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Theme.ink.opacity(0.08))
                .frame(width: 60, height: 12)
                .position(x: 70, y: 112)

            BlobShape()
                .fill(Theme.accent)

            Circle()
                .fill(Theme.paper)
                .frame(width: 8.4, height: 8.4)
                .position(x: 58, y: 70)
            Circle()
                .fill(Theme.paper)
                .frame(width: 8.4, height: 8.4)
                .position(x: 82, y: 70)

            MouthShape(smile: happy ? 8 : 3)
                .stroke(Theme.paper, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: Self.designSize.width, height: Self.designSize.height)
    }

    private var accessoryDots: some View {
        ForEach(Array(unlocked.enumerated()), id: \.element) { index, mode in
            Circle()
                .fill(mode.color)
                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                .frame(width: 14, height: 14)
                .position(Self.accessoryPositions[index % Self.accessoryPositions.count])
        }
    }
}

struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 70, y: 20))
        p.addCurve(to: CGPoint(x: 110, y: 66),
                   control1: CGPoint(x: 96, y: 20), control2: CGPoint(x: 110, y: 40))
        p.addCurve(to: CGPoint(x: 70, y: 106),
                   control1: CGPoint(x: 110, y: 90), control2: CGPoint(x: 92, y: 106))
        p.addCurve(to: CGPoint(x: 30, y: 66),
                   control1: CGPoint(x: 48, y: 106), control2: CGPoint(x: 30, y: 90))
        p.addCurve(to: CGPoint(x: 70, y: 20),
                   control1: CGPoint(x: 30, y: 40), control2: CGPoint(x: 44, y: 20))
        p.closeSubpath()
        return p
    }
}

struct MouthShape: Shape {
    var smile: CGFloat

    var animatableData: CGFloat {
        get { smile }
        set { smile = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 60, y: 84))
        p.addQuadCurve(to: CGPoint(x: 80, y: 84), control: CGPoint(x: 70, y: 84 + smile))
        return p
    }
}
