import SwiftUI

// MARK: - Tunables
// Every number the game balance depends on lives here and nowhere else.
enum Tunables {
    static let debtPerAvgDrink = 15.0
    static let debtCap = 100.0                  // debt = min(cap, (taps / headcount) × perDrink)
    static let redThreshold = 50.0              // LED red at/above; yellow 1–49; green at 0
    static let hydratePoints = 8.0
    static let hydrateCooldown: TimeInterval = 30 * 60
    static let movePerMin = 1.0
    static let deepWorkPerMin = 0.5
    static let restPerMin = 0.25
    static let decayPerHour = 2.0               // natural recovery, applied lazily
    static let defaultHeadcount = 4
    static let historyDayCount = 84             // 12 weeks
}

// MARK: - Faces
// The physical die has six faces. By night the pip count is the game input
// (dice language); by day the same face means an activity. One enum, two
// vocabularies — face index 0–5 is the order below, pips are 1–6.
enum Mode: String, CaseIterable, Codable {
    case deepWork, move, create, social, rest, hydrate

    static func fromFaceIndex(_ index: Int) -> Mode? {
        guard Mode.allCases.indices.contains(index) else { return nil }
        return Mode.allCases[index]
    }

    var faceIndex: Int { Mode.allCases.firstIndex(of: self) ?? 0 }

    var pipCount: Int { faceIndex + 1 }

    var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .move: return "Move"
        case .create: return "Create"
        case .social: return "Social"
        case .rest: return "Rest"
        case .hydrate: return "Hydrate"
        }
    }

    var color: Color {
        switch self {
        case .deepWork: return Color(hex: 0x3987E5)
        case .move: return Color(hex: 0xD95926)
        case .create: return Color(hex: 0xD55181)
        case .social: return Color(hex: 0xC98500)
        case .rest: return Color(hex: 0x199E70)
        case .hydrate: return Color(hex: 0x2FA8C9)
        }
    }

    // Not every face pays down debt — Create and Social are day meanings only.
    var recoveryKind: RecoveryKind? {
        switch self {
        case .deepWork: return .deepWork
        case .move: return .move
        case .rest: return .rest
        case .hydrate: return .hydrate
        case .create, .social: return nil
        }
    }
}

// MARK: - Party
struct RollEvent: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let face: Int                      // 1–6 pips
}

struct PartySession: Codable, Identifiable {
    var id = UUID()
    let startedAt: Date
    var endedAt: Date?
    var headcount: Int                 // set at session start, 1–10
    var drinkTaps: [Date] = []         // one entry per double-tap
    var rolls: [RollEvent] = []

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    var drinksPerPlayer: Double {
        guard headcount > 0 else { return Double(drinkTaps.count) }
        return Double(drinkTaps.count) / Double(headcount)
    }

    var startingDebt: Double {
        min(Tunables.debtCap, drinksPerPlayer * Tunables.debtPerAvgDrink)
    }

    // Busiest clock hour of the night, as a label. Nil until someone drinks.
    var peakHourLabel: String? {
        guard !drinkTaps.isEmpty else { return nil }
        let cal = Calendar.current
        let buckets = Dictionary(grouping: drinkTaps) { cal.component(.hour, from: $0) }
        guard let (hour, taps) = buckets.max(by: { $0.value.count < $1.value.count }) else { return nil }
        var components = DateComponents()
        components.hour = hour
        let date = cal.date(from: components) ?? Date()
        return "\(date.formatted(.dateTime.hour())) · \(taps.count)"
    }
}

// The deck is a plain array so swapping in another one later is trivial.
struct PartyRule: Identifiable {
    var id: Int { pips }
    let pips: Int
    let name: String
    let detail: String
    let promptsDrink: Bool
}

enum RuleDeck {
    static let name = "Cube's Cup"

    static let rules: [PartyRule] = [
        PartyRule(pips: 1, name: "Waterfall",
                  detail: "Everyone drinks until the roller stops.", promptsDrink: true),
        PartyRule(pips: 2, name: "You",
                  detail: "Pick someone. They drink.", promptsDrink: false),
        PartyRule(pips: 3, name: "Me",
                  detail: "That's you. Drink.", promptsDrink: true),
        PartyRule(pips: 4, name: "Categories",
                  detail: "Name a category. First to stall drinks.", promptsDrink: false),
        PartyRule(pips: 5, name: "Rule Maker",
                  detail: "Invent a rule. It holds all night.", promptsDrink: false),
        PartyRule(pips: 6, name: "Social",
                  detail: "Everyone drinks. Together.", promptsDrink: true),
    ]

    static func rule(forPips pips: Int) -> PartyRule {
        rules.first { $0.pips == pips } ?? rules[0]
    }
}

// MARK: - Recovery
enum RecoveryKind: String, Codable, CaseIterable {
    case hydrate, move, deepWork, rest, decay

    var pointsPerMinute: Double {
        switch self {
        case .move: return Tunables.movePerMin
        case .deepWork: return Tunables.deepWorkPerMin
        case .rest: return Tunables.restPerMin
        case .hydrate, .decay: return 0        // hydrate is instant, decay is hourly
        }
    }

    var displayName: String {
        switch self {
        case .hydrate: return "Hydrate"
        case .move: return "Move"
        case .deepWork: return "Deep Work"
        case .rest: return "Rest"
        case .decay: return "Time passing"
        }
    }

    var rateLabel: String {
        switch self {
        case .hydrate: return "+\(Int(Tunables.hydratePoints)) per glass"
        case .move: return "+1.0 / min"
        case .deepWork: return "+0.5 / min"
        case .rest: return "+0.25 / min"
        case .decay: return "+2 / hr"
        }
    }

    var color: Color {
        switch self {
        case .hydrate: return Mode.hydrate.color
        case .move: return Mode.move.color
        case .deepWork: return Mode.deepWork.color
        case .rest: return Mode.rest.color
        case .decay: return Theme.neutral
        }
    }
}

struct RecoveryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let kind: RecoveryKind
    let points: Double
}

// A face that's currently up and earning. Points are computed from wall time
// so the bar drains smoothly instead of jumping once a minute.
struct ActiveActivity: Codable {
    let kind: RecoveryKind
    var startedAt: Date

    func points(asOf now: Date) -> Double {
        max(0, now.timeIntervalSince(startedAt)) / 60 * kind.pointsPerMinute
    }
}

struct RecoveryDay: Codable {
    let date: Date
    var startingDebt: Double
    var entries: [RecoveryEntry] = []
    var active: ActiveActivity?
    var lastDecayAt: Date
    var clearedAt: Date?

    func earned(asOf now: Date) -> Double {
        entries.reduce(0) { $0 + $1.points } + (active?.points(asOf: now) ?? 0)
    }

    func debtRemaining(asOf now: Date) -> Double {
        max(0, startingDebt - earned(asOf: now))
    }

    var lastHydrateAt: Date? {
        entries.last { $0.kind == .hydrate }?.date
    }

    func hydrateReady(asOf now: Date) -> Bool {
        guard let last = lastHydrateAt else { return true }
        return now.timeIntervalSince(last) >= Tunables.hydrateCooldown
    }

    // 0…1 through the cooldown; 1 means ready.
    func hydrateCooldownProgress(asOf now: Date) -> Double {
        guard let last = lastHydrateAt else { return 1 }
        return min(1, max(0, now.timeIntervalSince(last) / Tunables.hydrateCooldown))
    }

    func total(for kind: RecoveryKind, asOf now: Date) -> Double {
        let logged = entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.points }
        if let active, active.kind == kind { return logged + active.points(asOf: now) }
        return logged
    }
}

enum DebtBand {
    case red, yellow, green

    static func band(for debt: Double) -> DebtBand {
        if debt <= 0 { return .green }
        return debt >= Tunables.redThreshold ? .red : .yellow
    }

    var color: Color {
        switch self {
        case .red: return Theme.debtRed
        case .yellow: return Theme.debtYellow
        case .green: return Theme.debtGreen
        }
    }

    var led: LEDCommand {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }

    // Always about the cube, never about the human holding it.
    var mascotLine: String {
        switch self {
        case .red: return "Cube's rough this morning."
        case .yellow: return "Cube's coming around."
        case .green: return "Cube's back. Nice."
        }
    }
}

// MARK: - Phase
enum CubePhase: Codable {
    case idle
    case party(PartySession)
    case recovery(RecoveryDay)

    var session: PartySession? {
        if case .party(let s) = self { return s }
        return nil
    }

    var recoveryDay: RecoveryDay? {
        if case .recovery(let d) = self { return d }
        return nil
    }
}

// MARK: - Day history
struct DayLog: Codable, Identifiable {
    var id = UUID()
    let date: Date
    var mode: Mode?
    var drinks: Int = 0
    var partyNight: Bool = false
    var cleared: Bool = false
}

// MARK: - LED
// Byte values written to the cube's LED characteristic.
enum LEDCommand: UInt8 {
    case off = 0
    case red = 1
    case yellow = 2
    case green = 3
    case partyPulse = 4
    case celebrate = 5
}
