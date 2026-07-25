# Today Cube — "Work Hard, Play Hard" Build Spec (for Claude Code)

## Context
Hackathon pivot, ~3h build budget for the app. There is an **existing Xcode project in `TodayCube/`** — extend it, don't start fresh. Reuse `CubeBLEManager`, `Theme`, `Components`, and the persistence pattern in `AppStore`. The old "life modes" concept is being repurposed, not deleted: the 6 faces keep their day meanings, but the app pivots around two modes — a nighttime drinking-game companion and a next-day recovery game.

The physical cube: ESP32 + MPU6050 + 4-color LED (blue, yellow, green, red). It detects which face is up, detects rolls and double-taps, and accepts LED color commands, all over BLE.

**Product loop:** at night the cube is the smart die running a drinking game and counting the table's drinks (double-tap = someone drank). Next morning the *cube* is "hungover": it glows red with a debt score, and the owner heals it back to green by doing healthy activities, logged by flipping the cube to the matching face. Same object collects the night and displays the morning.

**Narrative rule:** the debt belongs to the CUBE (mascot), not to a human. Copy should say things like "Cube is rough this morning" — never "you drank too much."

## Design principles — non-negotiable
- Minimalist but gamified: flat surfaces, generous padding, max two type scales per screen — the *game feel* comes from motion and moments (spring count-ups, bar drains, celebrations), not from decorative chrome.
- Party UI must be readable across a table in a dark room: huge type, high contrast.
- Drink counting is neutral documentation. No "new record!", no leaderboard, nothing that rewards a higher count.
- Recovery is a winnable game, never a scold. Red is a starting state, not a verdict.

## Visual style
`Mockup HTML file.html` in the repo root is the source of truth for palette, pip motif, and the calm "paper" feel — same as before. Hardcoded dark theme. Existing colors in `Theme.swift`:
- background `#0a0e0b`, paper `#14201b`, surface `#1c2a23`, surface-recede `#22302a`
- ink `#f3f1e7`, ink-secondary `#a8b0a6`, ink-muted `#75817a`, accent `#6fbfa0`
- Party accent: use deepWork blue `#3987e5` for night mode; debt bar uses red `#d95926`→yellow `#c98500`→green `#199e70` as it drains.

## Tech stack
Same as existing: SwiftUI, iOS 17+, CoreBluetooth, Codable → JSON in Documents, no SPM dependencies, runs on a physical iPhone with a free personal team.

## Data model (add to `Models.swift`)
```swift
struct RollEvent: Codable { let date: Date; let face: Int }        // 1–6 pips

struct PartySession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var headcount: Int                 // set at session start, 1–10
    var drinkTaps: [Date]              // one entry per double-tap
    var rolls: [RollEvent]
}

enum RecoveryKind: String, Codable { case hydrate, move, deepWork, rest, decay }

struct RecoveryEntry: Codable { let date: Date; let kind: RecoveryKind; let points: Double }

struct RecoveryDay: Codable {
    let date: Date
    var startingDebt: Double
    var entries: [RecoveryEntry]
    var debtRemaining: Double { max(0, startingDebt - entries.reduce(0) { $0 + $1.points }) }
}

enum CubePhase: Codable { case idle, party(PartySession), recovery(RecoveryDay) }
```

## All tunables in ONE place
```swift
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
}
```

## BLE protocol (extend `CubeBLEManager`)
Placeholder UUIDs as labeled constants, one-line swap when firmware lands:
- **Face char** (exists): notify UInt8 0–5 = face index.
- **Event char** (NEW): notify UInt8 — `0x01` roll-settled, `0x02` double-tap.
- **LED char** (NEW): write UInt8 — `0` off, `1` red, `2` yellow, `3` green, `4` blue party pulse, `5` green celebration blink.

Behavior:
- Party phase: `roll-settled` → read current face → append `RollEvent`, show rule card. `double-tap` → append drink tap.
- Recovery phase: face changes drive activity timers; whenever `debtRemaining` crosses a threshold band, write the matching LED byte (debounce: don't rewrite the same value).
- **Firmware fallback (build this in from the start):** if no `roll-settled` events arrive, infer a roll app-side — a burst of ≥2 face changes within 2s followed by ≥1s of one stable face = a roll onto that face. Gate this behind a bool so it can be flipped off when real events work.
- Keep existing graceful-disconnect + auto-reconnect behavior.

## App phases & screens
Root: two tabs — **Tonight** and **Today** — plus the phase state machine in `AppStore` (persist `CubePhase` across launches).

### Tonight tab (party) — build this FIRST
**Idle state:** one big button "Start the night" → sheet with a headcount slider (1–10, default 4) → creates `PartySession`, writes LED `4` (blue pulse).

**Live session — this screen is the game board, phone lies on the table:**
- Latest roll: pip icon + rule name HUGE (fills upper half, readable from 2m). On new roll: spring-scale entrance + brief background flash in the mode color of that face.
- Rule deck (constant array, swappable):
  1 Waterfall · 2 You (pick someone to drink) · 3 Me (you drink) · 4 Categories · 5 Rule maker · 6 Social (everyone drinks)
- Drink counter: big number with spring count-up animation on each double-tap + subtle haptic. Caption: "cube has had 6 drinks" (mascot frame).
- After a "Me" or "Social" roll: one-line hint "double-tap the cube when you drink."
- Small session stats row: rolls, duration.
- "End the night" → summary card: total drinks, drinks/player, rolls, duration, peak hour. CTA: "See you tomorrow ☀️". Ends session, computes `startingDebt = min(cap, (taps/headcount) × perDrink)`, creates tomorrow's `RecoveryDay`, phase → recovery.

### Today tab (recovery)
**With active `RecoveryDay`:**
- Cube mascot at top: rounded-square die face with two eyes + mouth (SwiftUI `Path`, reuse Pip drawing approach). Expression driven by debt band: red = wrecked (x eyes, wavy mouth), yellow = queasy, green = beaming. Body tint = band color.
- Debt bar: full-width, drains left→right, color shifts red→yellow→green with `debtRemaining`. Number label counts down with animation.
- Copy is always about the cube: "Cube's rough this morning — 90 to go."
- Activity logging (reuses face-up detection):
  - Current face-up shown as a card. If face maps to move / deepWork / rest, a live timer accrues points per `Tunables`, ticking every minute with a small "+1" float-up.
  - Hydrate: flipping to the rest/hydrate face gives instant `+8` with a splash animation, then a visible 30-min cooldown ring.
  - Natural decay: on app foreground, lazily add `decayPerHour × hoursElapsed` as a `.decay` entry (no background timers).
- Debt hits 0 → LED `5` (celebration blink), confetti, mascot beams, "Cube's back. Nice." Day marked cleared; keep it visible in the existing history grid if trivial, else skip.

**No active `RecoveryDay` (clean day):** mascot content + "Nothing to recover from. Green all day." LED `3`.

### Dev panel — MANDATORY, demo depends on it
Hidden behind triple-tap on any screen header. Buttons:
- Simulate roll (random face) · Simulate double-tap · Simulate face-up (per face)
- "Advance to morning" (ends session, jumps phase to recovery)
- "+1 hour" time skip (adds decay + advances cooldowns) · Force debt to 0
- Seed demo night (finished session: headcount 4, 24 taps → avg 6 → debt 90)
The demo must never depend on live BLE working in the room.

## Explicitly out of scope — do not build
Per-player tracking or player identity, multiple rule decks UI, BAC estimation of any kind, shop/currency/decorations, notifications, backend, theme toggle.

## Cut order if time runs short
1. History-grid integration → 2. Session summary card (just end quietly) → 3. deepWork/rest accrual (keep hydrate + move) → 4. Mascot expressions (keep static face + colored bar).
Never cut: dev panel, drink counter, debt bar, LED writes.

## Deliverable
The same Xcode project, still buildable and runnable on a physical iPhone with a personal team. Flag early if anything here looks like it'll blow the ~3h budget so scope gets cut instead of getting stuck.
