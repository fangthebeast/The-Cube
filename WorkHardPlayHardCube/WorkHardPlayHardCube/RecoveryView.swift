import SwiftUI

// The morning half. A debt you can win down, never a verdict you're stuck with.
struct RecoveryView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(eyebrow: store.recoveryDay == nil ? "TODAY" : "THE MORNING AFTER",
                                 title: "Work hard.",
                                 accent: palette.accent)

                    if store.recoveryDay != nil {
                        mascotCard
                        debtBar
                        activitySection
                        ledger
                    } else {
                        cleanDayCard
                    }

                    historySection

                    ConnectionDot(connected: ble.status == .connected, label: ble.status.label)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }

            if store.celebrating {
                ConfettiView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.celebrating)
    }

    // MARK: - Mascot

    private var mascotCard: some View {
        VStack(spacing: 14) {
            MascotView(band: store.band, size: 150)
                .animation(.easeInOut(duration: 0.4), value: store.band)

            Text(store.band.mascotLine)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)

            Text(subline)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 26)
    }

    private var subline: String {
        guard let day = store.recoveryDay else { return "" }
        if day.clearedAt != nil || store.debtRemaining <= 0 {
            return "Cleared for the day. Whatever you do next is just for you."
        }
        let remaining = Int(store.debtRemaining.rounded())
        return "\(remaining) to go. Water, a walk, a focus block — all of it counts."
    }

    // MARK: - Debt bar

    private var debtBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("CUBE'S DEBT")
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(palette.inkMuted)
                Spacer()
                Text("\(Int(store.debtRemaining.rounded()))")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(store.band.color)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.4), value: Int(store.debtRemaining.rounded()))
                Text("/ \(Int((store.recoveryDay?.startingDebt ?? 0).rounded()))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.inkMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surfaceRecede)
                    Capsule()
                        .fill(store.band.color)
                        .frame(width: max(0, geo.size.width * fillFraction))
                        .animation(.easeOut(duration: 0.6), value: fillFraction)
                        .animation(.easeInOut(duration: 0.5), value: store.band)
                }
            }
            .frame(height: 14)

            Text("\(Int((store.recoveryDay?.earned(asOf: store.now) ?? 0).rounded())) points paid down today")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.inkMuted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .card(cornerRadius: 20)
    }

    private var fillFraction: Double {
        guard let day = store.recoveryDay, day.startingDebt > 0 else { return 0 }
        return min(1, max(0, store.debtRemaining / day.startingDebt))
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT THE CUBE'S DOING")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)

            ActiveFaceCard()

            if let day = store.recoveryDay {
                HydrateCard(day: day, now: store.now)
            }

            Text("Flip the cube to the face you're actually on. Time on a face pays the debt down.")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.inkMuted)
                .lineSpacing(2)
        }
    }

    // MARK: - Ledger

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAID DOWN BY")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)

            VStack(spacing: 0) {
                ForEach(RecoveryKind.allCases, id: \.self) { kind in
                    let total = store.recoveryDay?.total(for: kind, asOf: store.now) ?? 0
                    if total > 0.05 {
                        HStack(spacing: 10) {
                            Circle().fill(kind.color).frame(width: 8, height: 8)
                            Text(kind.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Text(String(format: "+%.1f", total))
                                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.accent)
                        }
                        .padding(.vertical, 10)
                        Divider().overlay(palette.border)
                    }
                }
                if (store.recoveryDay?.earned(asOf: store.now) ?? 0) < 0.05 {
                    Text("Nothing yet. Flip to a face and it starts counting.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .card(cornerRadius: 20)
        }
    }

    // MARK: - Clean day

    private var cleanDayCard: some View {
        VStack(spacing: 14) {
            MascotView(band: .green, size: 140)
            Text("Nothing to recover from.")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.ink)
            Text("Green all day. The cube's just sitting here being smug about it.")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let face = store.currentFace {
                HStack(spacing: 10) {
                    DieFaceView(mode: face, size: 34)
                    Text("Face up: \(face.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.inkSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 26)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 12 weeks")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(store.totalDaysCleared) cleared · \(store.totalNightsLogged) nights")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.inkMuted)
            }
            HistoryGridView(history: store.history)
            HStack(spacing: 12) {
                legendDot(Theme.party, "night out")
                legendDot(Theme.debtGreen, "cleared")
                legendDot(palette.accent.opacity(0.28), "logged")
                legendDot(palette.surfaceRecede, "quiet")
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.inkSecondary)
        }
    }
}

// The face that's up right now, and what it's earning. Live — the points tick
// as the seconds pass rather than jumping once a minute.
private struct ActiveFaceCard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore

    @State private var floatKey = 0
    @State private var lastWholePoint = 0

    var body: some View {
        HStack(spacing: 14) {
            DieFaceView(mode: store.currentFace, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.currentFace?.displayName ?? "Waiting for a flip")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(statusLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkSecondary)
            }

            Spacer()

            if let active = store.recoveryDay?.active {
                ZStack(alignment: .trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "+%.1f", active.points(asOf: store.now)))
                            .font(.system(size: 19, weight: .black, design: .monospaced))
                            .foregroundStyle(active.kind.color)
                        Text(active.startedAt.distance(to: store.now).compactDuration)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.inkMuted)
                    }
                    FloatingPoint(key: floatKey, color: active.kind.color)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card(cornerRadius: 20)
        .onChange(of: wholePoints) { _, new in
            if new > lastWholePoint { floatKey += 1 }
            lastWholePoint = new
        }
        .onAppear { lastWholePoint = wholePoints }
    }

    private var wholePoints: Int {
        Int(store.recoveryDay?.active?.points(asOf: store.now) ?? 0)
    }

    private var statusLine: String {
        guard let face = store.currentFace else {
            return "Whichever face is up is what the cube's doing."
        }
        guard let kind = face.recoveryKind else {
            return "Nice, but it doesn't pay the debt down."
        }
        if kind == .hydrate { return "Water. \(kind.rateLabel)." }
        return "Earning \(kind.rateLabel)"
    }
}

// A "+1" that drifts up each time another whole point lands.
private struct FloatingPoint: View {
    let key: Int
    let color: Color

    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Text("+1")
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .offset(y: offset)
            .opacity(opacity)
            .onChange(of: key) { _, _ in
                offset = 0
                opacity = 1
                withAnimation(.easeOut(duration: 1.1)) {
                    offset = -34
                    opacity = 0
                }
            }
            .allowsHitTesting(false)
    }
}

// Hydrate is instant and capped by a visible cooldown ring — spam-flipping the
// cube gets you nothing.
private struct HydrateCard: View {
    @Environment(\.palette) private var palette

    let day: RecoveryDay
    let now: Date

    private var ready: Bool { day.hydrateReady(asOf: now) }
    private var progress: Double { day.hydrateCooldownProgress(asOf: now) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(palette.surfaceRecede, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Mode.hydrate.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Image(systemName: ready ? "drop.fill" : "hourglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Mode.hydrate.color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(ready ? "Water is ready" : "Water on cooldown")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(ready
                     ? "Flip to Hydrate when you drink a glass. +\(Int(Tunables.hydratePoints))."
                     : "Next glass counts in \(cooldownRemaining).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card(cornerRadius: 20)
    }

    private var cooldownRemaining: String {
        guard let last = day.lastHydrateAt else { return "now" }
        let remaining = Tunables.hydrateCooldown - now.timeIntervalSince(last)
        return max(0, remaining).compactDuration
    }
}

// 12 columns of 7 days. A day is one of: night out, cleared morning, a logged
// face, or quiet.
struct HistoryGridView: View {
    @Environment(\.palette) private var palette

    let history: [DayLog]

    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<12, id: \.self) { col in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let index = col * 7 + row
                        if index < history.count {
                            cell(for: history[index], isToday: index == history.count - 1)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    // Four states only — a rainbow of face colours would drown the two that
    // matter (a night out, and a morning cleared).
    private func color(for log: DayLog) -> Color {
        if log.cleared { return Theme.debtGreen }
        if log.partyNight { return Theme.party }
        if log.mode != nil { return palette.accent.opacity(0.28) }
        return palette.surfaceRecede
    }

    private func cell(for log: DayLog, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color(for: log))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.ink.opacity(0.55), lineWidth: 1.5)
                }
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
