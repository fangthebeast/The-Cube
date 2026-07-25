# Today Cube — "Work Hard, Play Hard" Pivot
### Plan + architecture · 3–4h hackathon build · 2026-07-24

## The one-liner
A smart die that runs your drinking game at night, remembers what you drank, and wakes up glowing red the next morning — a physical debt you pay down by doing healthy things until it turns green.

## Why the pivot works (and where the raw idea needed fixing)

| Raw idea | Problem | Fix |
|---|---|---|
| "Cube takes in drinks consumed" | Cube can't sense drinking | Double-tap the cube = "I drank." Tap detection is built into the MPU6050 (interrupt pin, ~20 min firmware). Theatrical, 1 second, part of the game ritual so people actually do it. |
| Cube at the party | If it only counts drinks, it's a worse phone app | The cube **is the die**. Roll → settles on a face → app announces that face's rule. Drinking games already revolve around dice; you're making the die smart. This is the demo hook. |
| "Shine red to reflect how net down I am" | Pure shame → cube goes in a drawer | Red isn't a verdict, it's the **starting state of a game you can win today**. LED = live progress bar that shifts red → orange → green as you log recovery. Debt is capped so a heavy night is never unwinnable. |
| "Make it green by logging healthy stuff" | How do you log? | Reuse what you built: **face-up = current activity**. Flip to Hydrate when you drink water, Move during a workout, Deep Work for a focus block. Time-on-face earns recovery points. Zero new sensing, zero new logging UI. |

The loop that makes the cube non-gimmicky: **the same physical object collects the night's data and then displays the morning's consequence.** Phone apps can't sit on your desk glowing.

## The two modes

Faces have pips 1–6. At night the **pip number** is the game input (dice language). By day the face means an **activity** (your existing Mode enum). Same faces, two vocabularies — no relabeling needed.

### 🌙 Party Mode (build first — priority)

**Enter:** app button ("Start the night") → one slider: **"How many players?"** (1–10). Cube LED goes to blue party pulse.

**The mascot frame:** the cube parties as hard as the table does. Every drink by *anyone* feeds the cube — next morning the *cube* is hungover and the owner nurses it back. This dissolves the "why am I clearing my friends' debt" problem (you're healing your cube, not their livers) and needs zero identity UX.

**Core loop — the smart die:**
1. Someone rolls the cube.
2. Firmware detects motion → stillness → sends `roll-settled` + face index.
3. Phone (face up on the table, acting as the game board) shows the rule big and loud:

| Pips | Rule (default deck "Cube's Cup") |
|---|---|
| 1 | **Waterfall** — everyone drinks until the roller stops |
| 2 | **You** — pick someone to drink |
| 3 | **Me** — you drink |
| 4 | **Categories** — loser drinks |
| 5 | **Rule maker** — invent a rule for the night |
| 6 | **Social** — everyone drinks |

Rules live in a plist/JSON array → trivially swappable decks later.

**Drink logging:** anyone finishes a drink → **double-tap the cube**. One communal counter — the app shows a satisfying +1 and timestamps every event. Optional: after a "Me"/"Social" roll, app prompts "double-tap when you drink" to train the habit.

**End the night:** app button → session summary card (total drinks, rolls, duration, drinks-per-hour curve) → data persists for tomorrow.

MVP scope call: one communal count + headcount. Per-player attribution is a v2 (each player's phone joins the session) — tonight's average-per-player proxy is honest about being a proxy, and that's the answer if judges push on it.

### ☀️ Recovery Mode (the morning after)

**Wake state:** app computes debt from last night, writes LED color to cube.

```
debt = min(100, (total_taps / headcount) × 15)   // avg player's night; solo (headcount 1) = personal tracking
LED:  red ≥ 50 · yellow 1–49 · green = 0 · blue = party mode
```

Debt reflects the *average player's* night — a decent proxy for the owner's without per-person tracking. The morning recap still shows the group totals (table drinks, rolls, peak hour) as the brag sheet; only the average drives debt.

**Paying it down (all reuse face-up detection):**

| Action | Points | Notes |
|---|---|---|
| Flip to Hydrate face when drinking water | +8 | 30-min cooldown so you can't spam-flip |
| Move face-up (walk/gym) | +1 / min | |
| Deep Work face-up | +0.5 / min | work counts as recovery — that's the brand |
| Rest face-up | +0.25 / min | |
| Natural decay | +2 / hr | honest: bodies recover on their own; cube just accelerates the feedback |

Sanity check: 6 drinks (debt 90) ≈ 3 waters + 45-min walk + 2h deep work + decay → green by evening. Requires real engagement, never hopeless.

**Hitting green:** LED celebration blink + app confetti + day is marked "cleared" in your existing history grid. Clean nights are just green all day.

Anti-cheat: don't bother. Timers make lying boring, and it's your own cube.

## Architecture

```
┌─ ESP32 + MPU6050 (+ RGB LED) ──────────────┐
│ face detect (exists)                        │
│ tap interrupt → double-tap event    (new)   │
│ motion→still → roll-settled event   (new)   │
│ LED driver ← BLE write              (new)   │
└──────────────┬──────────────────────────────┘
               │ BLE
┌─ iOS app (exists, extend) ──────────────────┐
│ CubeBLEManager  + event char, + LED write   │
│ AppStore        + PartySession, + debt      │
│ TonightView     rule cards, drink counter   │
│ TodayView       debt bar, activity timers   │
└─────────────────────────────────────────────┘
```

### BLE protocol (keep it bytes)
- **Face char** (exists): notify UInt8 0–5.
- **Event char** (new): notify UInt8 — `0x01` roll-settled, `0x02` double-tap.
- **LED char** (new): write UInt8 — `0` off · `1` red · `2` yellow · `3` green · `4` blue party pulse · `5` green celebration blink.

### Hardware: LED confirmed ✅
Four colors available: **blue, yellow, green, red**. Mapping: blue = play (party pulse at night), red/yellow/green = the recovery traffic light by day. Cleaner than the original orange plan. Fallback if LED wiring slips: the *phone* becomes the glow (full-screen ambient color, dock it face-up).

### Firmware fallbacks (agree on these with your partner now)
- Tap detection flaky → face 3 ("Me") doubles as the drink face, or app button.
- No roll-settled event → app infers a roll from rapid face-change bursts followed by 1s of a stable face. Pure iOS, zero firmware.
- Any BLE failure on stage → manual override buttons already in your demo plan; keep them.

## Build plan (3–4h, two people in parallel)

| Hour | iOS (you) | Firmware (partner) |
|---|---|---|
| 1 | Data model: `PartySession`, `DrinkEvent`, debt calc. TonightView skeleton with **simulated cube buttons** so you're never blocked on hardware. | Tap interrupt + double-tap debounce. Agree byte protocol (10 min, together, first). |
| 2 | Rule deck + roll-result cards + drink counter + session summary. | Roll-settled detection. LED write char + colors. |
| 3 | Recovery view: debt bar, LED write on debt change, face-timer accrual, hydrate cooldown. "Advance to morning" dev button. | Integration on real hardware. Party/celebration LED animations. |
| 4 | Polish + rehearse demo twice. | Buffer — something above will have slipped. |

**Cut order if behind:** LED animations → session summary card → deep-work/rest accrual (keep hydrate + move) → roll-settled (manual "we rolled" tap in app).

## Demo script (~90 seconds)
1. "It's Friday night." Start Party Mode — cube pulses. Roll it on the table → phone booms "WATERFALL." Crowd moment.
2. Double-tap ×6 fast — counter climbs to 6 drinks. "The cube remembers so you don't have to."
3. Dev button: "It's Saturday morning." Cube glows **red**. Debt bar: 90.
4. Drink water on stage, flip to Hydrate → +8, bar drains, LED shifts. Flip to Move → points tick live.
5. Force-clear → **green** + celebration. "Work hard, play hard — same cube, both halves of your life."

## One flag worth 10 seconds of thought
Keep the drink counter **neutral documentation**, never a leaderboard or achievement ("new record: 9 drinks!" = bad). Judges will ask about responsible-use; your answer: the cube is the only party product whose incentive points *toward* recovery — the fun of clearing the debt is the moderation mechanic.
