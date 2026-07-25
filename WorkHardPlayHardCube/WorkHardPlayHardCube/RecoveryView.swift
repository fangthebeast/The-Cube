import SwiftUI

// The morning half. Two states and nothing in between: either the cube owes
// something and the screen is about paying it down, or it doesn't and the
// screen gets out of the way.
struct RecoveryView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager

    private var hasDebt: Bool { store.recoveryDay != nil && store.debtRemaining > 0 }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(eyebrow: hasDebt ? "THE MORNING AFTER" : "TODAY",
                                 title: "Work hard.",
                                 accent: palette.accent)
                    statusPill

                    if hasDebt {
                        debtHero
                        RightNowCard()
                        FaceRulesCard(eyebrow: "HOW TO PAY IT DOWN")
                    } else {
                        clearCard
                        FaceRulesCard(eyebrow: "WHAT EACH FACE MEANS")
                    }

                    HistoryCalendarView(history: store.history)
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

    // MARK: - Header pill

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ble.status == .connected ? palette.accent : palette.inkMuted)
                .frame(width: 6, height: 6)
            Text(ble.status.label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(palette.surface))
        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - State A: debt

    // Mascot and debt are one thing, so they live on one card.
    private var debtHero: some View {
        VStack(spacing: 14) {
            MascotView(band: store.band, size: 128)
                .animation(.easeInOut(duration: 0.4), value: store.band)

            Text(store.band.mascotLine)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.ink)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(Int(store.debtRemaining.rounded()))")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(store.band.color)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.4), value: Int(store.debtRemaining.rounded()))
                Text("to go")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.inkSecondary)
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
            .frame(height: 8)

            VStack(spacing: 3) {
                Text("\(Int(earnedToday.rounded())) paid down today")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                Text("Flip the cube to pay it down.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 26)
    }

    private var earnedToday: Double {
        store.recoveryDay?.earned(asOf: store.now) ?? 0
    }

    private var fillFraction: Double {
        guard let day = store.recoveryDay, day.startingDebt > 0 else { return 0 }
        return min(1, max(0, store.debtRemaining / day.startingDebt))
    }

    // MARK: - State B: nothing owed

    private var clearCard: some View {
        VStack(spacing: 14) {
            MascotView(band: .green, size: 140)
            Text(store.recoveryDay == nil ? "Nothing to recover from." : "Cube's back. Nice.")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.ink)
            Text(store.recoveryDay == nil
                 ? "Green all day."
                 : "Cleared for the day. Whatever you do next is just for you.")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 26)
    }
}

// What every face is worth, in two tiers. Titled "how to pay it down" while
// there's a debt and plain reference once there isn't.
struct FaceRulesCard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore

    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)

            VStack(spacing: 16) {
                tier("ACTIVE", modes: [.move, .deepWork, .create])
                tier("RESTORE", modes: [.social, .rest, .hydrate])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .card(cornerRadius: 20)
        }
    }

    private func tier(_ title: String, modes: [Mode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted.opacity(0.8))
            ForEach(modes, id: \.self) { mode in
                HStack(spacing: 12) {
                    DieFaceView(mode: mode, size: 32)
                    Text(mode.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(mode.recoveryKind.rateLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.currentFace == mode ? palette.accent : palette.inkSecondary)
                }
            }
        }
    }
}

// The one and only current-state card: what face is up, what it's earning, and
// how to log a face by hand when the cube isn't connected.
private struct RightNowCard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager

    @State private var floatKey = 0
    @State private var lastWholePoint = 0

    private var face: Mode? { store.currentFace }
    private var day: RecoveryDay? { store.recoveryDay }
    private var needsManualLog: Bool { face == nil || ble.status != .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RIGHT NOW")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)

            HStack(spacing: 14) {
                leading

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if let active = day?.active {
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

            if needsManualLog { manualRow }
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

    @ViewBuilder
    private var leading: some View {
        if face == .hydrate, let day {
            HydrateRing(progress: day.hydrateCooldownProgress(asOf: store.now),
                        ready: day.hydrateReady(asOf: store.now))
        } else {
            DieFaceView(mode: face, size: 50)
        }
    }

    private var title: String {
        guard let face else {
            return ble.status == .connected ? "Waiting for a flip" : "Cube not connected"
        }
        return face.displayName
    }

    private var subtitle: String {
        guard let face else {
            return ble.status == .connected
                ? "Whichever face lands starts earning."
                : "Tap the face you're on to log it by hand."
        }
        if face == .hydrate, let day {
            return day.hydrateReady(asOf: store.now)
                ? "Ready — +\(Int(Tunables.hydratePoints)) the next time you flip here."
                : "Logged. Next glass counts in \(cooldownRemaining)."
        }
        return "Earning \(face.recoveryKind.rateLabel)"
    }

    private var cooldownRemaining: String {
        guard let last = day?.lastHydrateAt else { return "a moment" }
        return max(0, Tunables.hydrateCooldown - store.now.timeIntervalSince(last)).compactDuration
    }

    private var wholePoints: Int {
        Int(day?.active?.points(asOf: store.now) ?? 0)
    }

    private var manualRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Button {
                        Haptics.tap(.light)
                        store.setFace(mode)
                    } label: {
                        DieFaceView(mode: mode, size: 36)
                            .overlay {
                                if store.currentFace == mode {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(palette.ink, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Log a face by hand")
                .font(.system(size: 11))
                .foregroundStyle(palette.inkMuted)
        }
    }
}

// Hydrate's cooldown, in place of the die face while that face is up.
private struct HydrateRing: View {
    @Environment(\.palette) private var palette

    let progress: Double
    let ready: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(palette.surfaceRecede, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Mode.hydrate.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Image(systemName: ready ? "drop.fill" : "hourglass")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Mode.hydrate.color)
        }
        .frame(width: 50, height: 50)
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

// A plain month calendar — day numbers, weekday columns, one month at a time.
// A day is one of: night out, cleared morning, a logged face, or quiet.
struct HistoryCalendarView: View {
    @Environment(\.palette) private var palette

    let history: [DayLog]

    @State private var monthOffset = 0        // 0 = this month, -1 = last month

    private var cal: Calendar { Calendar.current }

    private var thisMonth: Date {
        let now = cal.startOfDay(for: Date())
        return cal.date(from: cal.dateComponents([.year, .month], from: now))!
    }

    private var shownMonth: Date {
        cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    // History only goes back 12 weeks, so there's nothing to page to beyond it.
    private var earliestMonth: Date {
        guard let first = history.first?.date else { return thisMonth }
        return cal.date(from: cal.dateComponents([.year, .month], from: first)) ?? thisMonth
    }

    private var canGoBack: Bool { shownMonth > earliestMonth }
    private var canGoForward: Bool { monthOffset < 0 }

    // Day-of-month lookup for the shown month.
    private var logsByDay: [Date: DayLog] {
        Dictionary(history.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, last in last })
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    // Leading blanks before the 1st, then every day of the month.
    private var slots: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: shownMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: shownMonth)
        let blanks = (firstWeekday - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: shownMonth) }
        return Array(repeating: nil, count: blanks) + days.map { Optional($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            monthBar
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(for: day)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .card(cornerRadius: 20)
    }

    private var monthBar: some View {
        HStack {
            arrow("chevron.left", enabled: canGoBack) { monthOffset -= 1 }
            Spacer()
            Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.ink)
            Spacer()
            arrow("chevron.right", enabled: canGoForward) { monthOffset += 1 }
        }
    }

    private func arrow(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? palette.inkSecondary : palette.inkMuted.opacity(0.35))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Four states only — a rainbow of face colours would drown the two that
    // matter (a night out, and a morning cleared).
    private func fill(for log: DayLog?) -> Color {
        guard let log else { return .clear }
        if log.cleared { return Theme.debtGreen }
        if log.partyNight { return Theme.party }
        if log.mode != nil { return palette.accent.opacity(0.28) }
        return palette.surfaceRecede
    }

    private func numberColor(for log: DayLog?) -> Color {
        guard let log else { return palette.inkMuted.opacity(0.5) }
        if log.cleared || log.partyNight { return .white }
        if log.mode != nil { return palette.ink }
        return palette.inkSecondary
    }

    private func cell(for day: Date) -> some View {
        let log = logsByDay[cal.startOfDay(for: day)]
        let isToday = cal.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill(for: log))
            .overlay {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12.5, weight: isToday ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(numberColor(for: log))
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.ink.opacity(0.55), lineWidth: 1.5)
                }
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
