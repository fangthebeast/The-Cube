import SwiftUI

// All app state: the phase machine (idle → party → recovery), 12 weeks of day
// logs, and the debt math. Persisted as JSON in Documents.
//
// Narrative rule enforced throughout: the debt belongs to the CUBE, not to a
// person. Nothing here ranks, rewards or scolds a drink count.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var phase: CubePhase = .idle
    @Published private(set) var history: [DayLog] = []
    @Published private(set) var currentFace: Mode?
    @Published private(set) var lastSummary: PartySession?   // last finished night
    @Published private(set) var celebrating = false
    @Published private(set) var hydrateSplash = 0            // bumps to trigger the splash
    @Published private(set) var drinkPulse = 0               // bumps on every tap
    @Published private(set) var rollPulse = 0                // bumps on every roll

    // Ticked every second so time-based points drain the bar smoothly.
    @Published private(set) var now = Date()

    // Wired up in WorkHardPlayHardCubeApp; nil until BLE exists.
    var onLED: ((LEDCommand) -> Void)?

    private var lastLEDWritten: LEDCommand?
    private var ticker: Timer?

    private struct Persisted: Codable {
        var history: [DayLog]
        var phase: CubePhase
        var lastSummary: PartySession?
    }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workhardplayhardcube.json")
    }

    init() {
        if !load() { seedHistory() }
        rollForwardToToday()
        applyDecay()
        startTicking()
    }

    // MARK: - Derived state

    var session: PartySession? { phase.session }
    var recoveryDay: RecoveryDay? { phase.recoveryDay }

    var isPartying: Bool { session != nil }

    var latestRoll: RollEvent? { session?.rolls.last }

    var latestRule: PartyRule? { latestRoll.map { RuleDeck.rule(forPips: $0.face) } }

    var drinkCount: Int { session?.drinkTaps.count ?? 0 }

    var debtRemaining: Double { recoveryDay?.debtRemaining(asOf: now) ?? 0 }

    var band: DebtBand { DebtBand.band(for: debtRemaining) }

    var debtProgress: Double {
        guard let day = recoveryDay, day.startingDebt > 0 else { return 1 }
        return 1 - (debtRemaining / day.startingDebt)
    }

    var activeKind: RecoveryKind? { recoveryDay?.active?.kind }

    var hydrateReady: Bool { recoveryDay?.hydrateReady(asOf: now) ?? true }

    var totalNightsLogged: Int { history.filter { $0.partyNight }.count }
    var totalDaysCleared: Int { history.filter { $0.cleared }.count }

    // MARK: - Party

    func startNight(headcount: Int) {
        let session = PartySession(startedAt: Date(), headcount: max(1, min(10, headcount)))
        phase = .party(session)
        markToday { $0.partyNight = true }
        refreshLED()
        save()
    }

    // Called by the cube's roll-settled event, by the app-side roll inference,
    // and by the dev panel. Uses the face that's up unless one is passed in.
    func registerRoll(face: Mode? = nil) {
        guard var session = phase.session else { return }
        let landed = face ?? currentFace ?? Mode.allCases.randomElement()!
        currentFace = landed
        session.rolls.append(RollEvent(date: Date(), face: landed.pipCount))
        phase = .party(session)
        rollPulse &+= 1
        Haptics.tap(.rigid)
        save()
    }

    // One double-tap = one drink at the table. Neutral documentation only.
    func registerDrinkTap() {
        guard var session = phase.session else { return }
        session.drinkTaps.append(Date())
        phase = .party(session)
        drinkPulse &+= 1
        markToday { $0.drinks += 1 }
        Haptics.tap(.light)
        save()
    }

    // Ends the night, banks the summary, and opens the morning's recovery day.
    func endNight() {
        guard var session = phase.session else { return }
        session.endedAt = Date()
        lastSummary = session
        beginRecovery(startingDebt: session.startingDebt)
    }

    private func beginRecovery(startingDebt: Double) {
        var day = RecoveryDay(
            date: Date(),
            startingDebt: startingDebt,
            entries: [],
            active: nil,
            lastDecayAt: Date(),
            clearedAt: nil
        )
        // Whatever face is already up starts earning immediately — the cube
        // doesn't need to be flipped twice.
        if let kind = currentFace?.recoveryKind, kind.pointsPerMinute > 0 {
            day.active = ActiveActivity(kind: kind, startedAt: Date())
        }
        phase = .recovery(day)

        // A night with nothing to pay off is already clear.
        if day.debtRemaining(asOf: Date()) <= 0 {
            markCleared()
        } else {
            refreshLED()
        }
        save()
    }

    // MARK: - Faces & recovery accrual

    // Every face change: BLE notification or dev panel. Drives the day log and,
    // in recovery, the activity timers.
    func setFace(_ mode: Mode) {
        guard mode != currentFace else { return }
        currentFace = mode
        markToday { $0.mode = mode }

        if var day = phase.recoveryDay {
            commitActive(&day)
            if let kind = mode.recoveryKind {
                if kind == .hydrate {
                    awardHydrate(&day)
                } else {
                    day.active = ActiveActivity(kind: kind, startedAt: Date())
                }
            }
            phase = .recovery(day)
            refreshLED()
        }
        save()
    }

    private func commitActive(_ day: inout RecoveryDay) {
        guard let active = day.active else { return }
        let points = active.points(asOf: Date())
        if points > 0.01 {
            day.entries.append(RecoveryEntry(date: Date(), kind: active.kind, points: points))
        }
        day.active = nil
    }

    private func awardHydrate(_ day: inout RecoveryDay) {
        guard day.hydrateReady(asOf: Date()) else { return }
        day.entries.append(RecoveryEntry(date: Date(), kind: .hydrate, points: Tunables.hydratePoints))
        hydrateSplash &+= 1
        Haptics.tap(.medium)
    }

    // Bodies recover on their own — applied lazily on launch and foreground,
    // never with a background timer.
    func applyDecay() {
        guard var day = phase.recoveryDay else { return }
        let hours = Date().timeIntervalSince(day.lastDecayAt) / 3600
        guard hours > 0 else { return }
        let points = hours * Tunables.decayPerHour
        if points > 0.05 {
            day.entries.append(RecoveryEntry(date: Date(), kind: .decay, points: points))
        }
        day.lastDecayAt = Date()
        phase = .recovery(day)
        refreshLED()
        save()
    }

    // MARK: - Ticking

    private func startTicking() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        guard let day = phase.recoveryDay else { return }
        if day.clearedAt == nil, day.debtRemaining(asOf: now) <= 0 {
            markCleared()
        } else {
            refreshLED()
        }
    }

    private func markCleared() {
        guard var day = phase.recoveryDay, day.clearedAt == nil else { return }
        commitActive(&day)
        day.clearedAt = Date()
        phase = .recovery(day)
        markToday { $0.cleared = true }
        celebrating = true
        Haptics.success()
        writeLED(.celebrate)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            celebrating = false
            refreshLED()
        }
        save()
    }

    // MARK: - LED

    private func refreshLED() {
        guard !celebrating else { return }
        switch phase {
        case .party:
            writeLED(.partyPulse)
        case .recovery:
            writeLED(band.led)
        case .idle:
            writeLED(.green)
        }
    }

    // Debounced: never rewrite a value the cube already has.
    private func writeLED(_ command: LEDCommand) {
        guard command != lastLEDWritten else { return }
        lastLEDWritten = command
        onLED?(command)
    }

    // Called once BLE (re)connects, so the cube catches up with app state.
    func resendLED() {
        lastLEDWritten = nil
        refreshLED()
    }

    var currentLED: LEDCommand {
        if celebrating { return .celebrate }
        switch phase {
        case .party: return .partyPulse
        case .recovery: return band.led
        case .idle: return .green
        }
    }

    // MARK: - Dev panel

    // Ends any live night and drops straight into the morning after.
    func advanceToMorning() {
        if isPartying {
            endNight()
        } else if phase.recoveryDay == nil {
            seedDemoNight()
        }
    }

    // A finished night: 4 players, 24 taps → 6 avg → debt 90.
    func seedDemoNight() {
        let start = Date().addingTimeInterval(-5 * 3600)
        var session = PartySession(startedAt: start, headcount: 4)
        session.endedAt = Date().addingTimeInterval(-1 * 3600)
        session.drinkTaps = (0..<24).map { start.addingTimeInterval(Double($0) * 600) }
        session.rolls = (0..<14).map {
            RollEvent(date: start.addingTimeInterval(Double($0) * 1000),
                      face: Int.random(in: 1...6))
        }
        lastSummary = session

        celebrating = false
        beginRecovery(startingDebt: session.startingDebt)
        markToday {
            $0.partyNight = true
            $0.drinks = 24
            $0.cleared = false
        }
        resendLED()
        save()
    }

    // Shifts every timestamp back an hour: decay lands, cooldowns expire,
    // whatever face is up keeps earning.
    func skipHour() {
        guard var day = phase.recoveryDay else { return }
        let hour: TimeInterval = -3600
        day.entries = day.entries.map {
            RecoveryEntry(id: $0.id, date: $0.date.addingTimeInterval(hour), kind: $0.kind, points: $0.points)
        }
        day.active?.startedAt.addTimeInterval(hour)
        day.lastDecayAt.addTimeInterval(hour)
        phase = .recovery(day)
        applyDecay()
    }

    func forceClearDebt() {
        guard var day = phase.recoveryDay else { return }
        let remaining = day.debtRemaining(asOf: Date())
        if remaining > 0 {
            day.entries.append(RecoveryEntry(date: Date(), kind: .decay, points: remaining))
        }
        phase = .recovery(day)
        markCleared()
    }

    func resetToIdle() {
        phase = .idle
        lastSummary = nil
        celebrating = false
        resendLED()
        save()
    }

    // MARK: - History

    func rollForwardToToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let last = history.last else { return }
        var lastDate = cal.startOfDay(for: last.date)
        var changed = false
        while lastDate < today {
            lastDate = cal.date(byAdding: .day, value: 1, to: lastDate)!
            history.append(DayLog(date: lastDate))
            changed = true
        }
        if history.count > Tunables.historyDayCount {
            history.removeFirst(history.count - Tunables.historyDayCount)
        }
        if changed { save() }
    }

    private func markToday(_ mutate: (inout DayLog) -> Void) {
        guard !history.isEmpty else { return }
        mutate(&history[history.count - 1])
    }

    // MARK: - Persistence

    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data),
              !persisted.history.isEmpty else { return false }
        history = persisted.history
        phase = persisted.phase
        lastSummary = persisted.lastSummary
        return true
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshot = Persisted(history: history, phase: phase, lastSummary: lastSummary)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // A plausible 12 weeks so the grid isn't empty on first launch. No debt,
    // no judgement — just a few nights out and a few cleared mornings.
    private func seedHistory() {
        var rng = SeededGenerator(state: 0x5EED_C0BE)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var logs: [DayLog] = []

        for daysAgo in stride(from: Tunables.historyDayCount - 1, through: 1, by: -1) {
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            var log = DayLog(date: date)
            let weekday = cal.component(.weekday, from: date)
            let isWeekendNight = weekday == 6 || weekday == 7
            if isWeekendNight, Double.random(in: 0..<1, using: &rng) < 0.55 {
                log.partyNight = true
                log.drinks = Int.random(in: 6...22, using: &rng)
                log.cleared = Double.random(in: 0..<1, using: &rng) < 0.7
            } else if Double.random(in: 0..<1, using: &rng) < 0.8 {
                log.mode = Mode.allCases.randomElement(using: &rng)
            }
            logs.append(log)
        }
        logs.append(DayLog(date: today))
        history = logs
        save()
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}
