import SwiftUI

// All app state: 12 weeks of day logs, persisted as JSON in Documents.
// Gain-framed on purpose: nothing here ever decays or resets.
@MainActor
final class AppStore: ObservableObject {
    static let dayCount = 84 // 12 weeks

    @Published private(set) var history: [DayLog] = []
    @Published private(set) var unlockedModes: Set<Mode> = []

    private struct Persisted: Codable {
        var history: [DayLog]
        var unlockedModes: Set<Mode>
    }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todaycube.json")
    }

    init() {
        if !load() {
            seedDemoData()
        }
        rollForwardToToday()
    }

    // MARK: - Derived state

    var currentMode: Mode? { history.last?.mode }
    var todayLogged: Bool { currentMode != nil }

    var counts: [Mode: Int] {
        history.reduce(into: [:]) { acc, log in
            if let m = log.mode { acc[m, default: 0] += 1 }
        }
    }

    var totalLogged: Int { history.filter { $0.mode != nil }.count }

    var restShare: Double {
        let total = totalLogged
        guard total > 0 else { return 0 }
        return Double(counts[.rest] ?? 0) / Double(total)
    }

    var showNudge: Bool { restShare > 0.35 }

    var pipStage: Int { totalLogged > 50 ? 3 : totalLogged > 20 ? 2 : 1 }

    var pipStageLabel: String {
        switch pipStage {
        case 1: return "Stage 1 — Just hatched"
        case 2: return "Stage 2 — Settling in"
        default: return "Stage 3 — Fully at home"
        }
    }

    // MARK: - Mutations

    // Called on every BLE face update and by the manual dev override.
    func setTodayMode(_ mode: Mode) {
        guard !history.isEmpty else { return }
        history[history.count - 1].mode = mode
        updateUnlocks()
        save()
    }

    // Extends history to today after a day rollover (app left open overnight,
    // or reopened days later). New days start unlogged; window stays 84 days.
    func rollForwardToToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let last = history.last else { return }
        var lastDate = cal.startOfDay(for: last.date)
        var changed = false
        while lastDate < today {
            lastDate = cal.date(byAdding: .day, value: 1, to: lastDate)!
            history.append(DayLog(id: UUID(), date: lastDate, mode: nil))
            changed = true
        }
        if history.count > Self.dayCount {
            history.removeFirst(history.count - Self.dayCount)
        }
        if changed { save() }
    }

    private func updateUnlocks() {
        // Unlocks are permanent — modes are only ever added, never removed.
        for mode in Mode.allCases where (counts[mode] ?? 0) >= 3 {
            unlockedModes.insert(mode)
        }
    }

    // MARK: - Persistence

    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data),
              !persisted.history.isEmpty else { return false }
        history = persisted.history
        unlockedModes = persisted.unlockedModes
        return true
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Persisted(history: history, unlockedModes: unlockedModes)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Demo seed

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    // ~12 weeks of plausible history; the recent days lean Rest so the nudge
    // banner is demoable immediately. Today starts unlogged and fills in live.
    private func seedDemoData() {
        var rng = SeededGenerator(state: 0x5EED_C0BE)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var logs: [DayLog] = []

        for daysAgo in stride(from: Self.dayCount - 1, through: 1, by: -1) {
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            var mode: Mode?
            if daysAgo <= 5 {
                let others: [Mode] = [.deepWork, .move, .social, .rest, .admin]
                mode = Double.random(in: 0..<1, using: &rng) < 0.75
                    ? .rest
                    : others.randomElement(using: &rng)
            } else if Double.random(in: 0..<1, using: &rng) < 0.82 {
                let weighted: [Mode] = [.deepWork, .deepWork, .move, .social, .rest, .rest, .admin]
                mode = weighted.randomElement(using: &rng)
            }
            logs.append(DayLog(id: UUID(), date: date, mode: mode))
        }

        logs.append(DayLog(id: UUID(), date: today, mode: nil))
        history = logs

        // Exactly two Create days in the seed: the third Create log — the first
        // live flip to Create in the demo — unlocks its accessory on stage.
        history[20].mode = .create
        history[45].mode = .create

        // Guarantee the nudge threshold is crossed regardless of RNG drift,
        // converting the most recent non-rest days first (Create days excluded
        // so the live-unlock setup stays intact).
        var index = history.count - 2
        while restShare <= 0.36 && index >= 0 {
            let mode = history[index].mode
            if mode != nil && mode != .rest && mode != .create {
                history[index].mode = .rest
            }
            index -= 1
        }

        updateUnlocks()
        save()
    }
}
