import SwiftUI

// The night half. When a session is live this screen is the game board — the
// phone lies face-up on the table and has to read from two metres away.
struct TonightView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager
    @EnvironmentObject private var ui: UIState

    @State private var showHeadcount = false
    @State private var showRules = false
    @State private var showSummary = false
    @State private var headcount = Double(Tunables.defaultHeadcount)

    var body: some View {
        Group {
            if store.isPartying {
                liveBoard
            } else {
                idle
            }
        }
        .sheet(isPresented: $showHeadcount) { headcountSheet }
        .sheet(isPresented: $showSummary) { summarySheet }
        .sheet(isPresented: $showRules) { rulesSheet }
    }

    // MARK: - Idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(eyebrow: "TONIGHT", title: "Play hard.", accent: Theme.party)

                VStack(spacing: 16) {
                    DieFaceView(mode: .social, size: 96)
                        .shadow(color: Theme.party.opacity(0.25), radius: 24, y: 8)
                    Text("The cube is the die.")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(palette.ink)
                    Text("Roll it and it calls the shot. Double-tap it whenever someone finishes a drink — the cube keeps count so nobody has to.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .card(cornerRadius: 26)

                BigButton(title: "Start the night", tint: Theme.party) {
                    headcount = Double(Tunables.defaultHeadcount)
                    showHeadcount = true
                }

                RuleDeckCard()

                if let last = store.lastSummary {
                    lastNightCard(last)
                }

                ConnectionDot(connected: ble.status == .connected, label: ble.status.label)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func lastNightCard(_ session: PartySession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST NIGHT")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)
            HStack(spacing: 10) {
                StatTile(value: "\(session.drinkTaps.count)", label: "table drinks")
                StatTile(value: "\(session.rolls.count)", label: "rolls")
                StatTile(value: session.duration.compactDuration, label: "on the table")
            }
        }
    }

    // MARK: - Headcount sheet

    private var headcountSheet: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOW MANY PLAYERS?")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(palette.inkMuted)
                Text("The cube splits the night between everyone at the table.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.inkSecondary)
                    .lineSpacing(3)
            }

            Text("\(Int(headcount))")
                .font(.system(size: 76, weight: .black, design: .rounded))
                .foregroundStyle(Theme.party)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.25), value: headcount)

            Slider(value: $headcount, in: 1...10, step: 1)
                .tint(Theme.party)

            BigButton(title: "Let's go", tint: Theme.party) {
                store.startNight(headcount: Int(headcount))
                showHeadcount = false
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paper.ignoresSafeArea())
        .presentationDetents([.height(380)])
    }

    // MARK: - Live board

    private var liveBoard: some View {
        VStack(spacing: 16) {
            boardHeader
            rollCard
            drinkCounter
            statsRow
            BigButton(title: "End the night", tint: palette.inkSecondary, filled: false) {
                store.endNight()
                showSummary = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var boardHeader: some View {
        HStack(alignment: .center) {
            ScreenHeader(eyebrow: "PARTY MODE · \(RuleDeck.name.uppercased())",
                         title: "Roll it.",
                         accent: Theme.party)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let session = store.session {
                    Text(session.duration.compactDuration)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.inkMuted)
                }
                Button { showRules = true } label: {
                    Text("Rules")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.party)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rollCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.surface)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)

            if let rule = store.latestRule, let roll = store.latestRoll {
                RollResultView(rule: rule, roll: roll)
            } else {
                VStack(spacing: 14) {
                    DieFaceView(mode: store.currentFace, size: 76)
                        .opacity(0.7)
                    Text("Roll the cube")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.inkSecondary)
                    Text("Whatever face lands, the table plays it.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var drinkCounter: some View {
        DrinkCounterView(count: store.drinkCount,
                         pulse: store.drinkPulse,
                         promptsDrink: store.latestRule?.promptsDrink ?? false)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(store.session?.rolls.count ?? 0)", label: "rolls")
            StatTile(value: "\(store.session?.headcount ?? 0)", label: "players")
            StatTile(value: String(format: "%.1f", store.session?.drinksPerPlayer ?? 0),
                     label: "avg / player")
        }
    }

    // MARK: - Summary

    private var summarySheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THE NIGHT")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(palette.inkMuted)
                Text(summaryTitle)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.ink)
            }

            if let session = store.lastSummary {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        StatTile(value: "\(session.drinkTaps.count)", label: "table drinks")
                        StatTile(value: String(format: "%.1f", session.drinksPerPlayer),
                                 label: "per player")
                    }
                    HStack(spacing: 10) {
                        StatTile(value: "\(session.rolls.count)", label: "rolls")
                        StatTile(value: session.duration.compactDuration, label: "duration")
                    }
                    if let peak = session.peakHourLabel {
                        HStack(spacing: 10) {
                            StatTile(value: peak, label: "busiest hour")
                        }
                    }
                }

                Text(session.startingDebt <= 0
                     ? "Nothing to sleep off. The cube wakes up green."
                     : "Tomorrow the cube wakes up at \(Int(session.startingDebt.rounded())). You'll help it down.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.inkSecondary)
                    .lineSpacing(3)
            }

            Spacer()

            BigButton(title: "See you tomorrow ☀️") {
                showSummary = false
                ui.tab = .today
            }
        }
        .padding(24)
        .background(palette.paper.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private var rulesSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Whatever it lands on, the table plays.")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.ink)
                RuleDeckCard()
                BigButton(title: "Back to the game", tint: Theme.party) { showRules = false }
            }
            .padding(24)
        }
        .background(palette.paper.ignoresSafeArea())
    }

    private var summaryTitle: String {
        (store.lastSummary?.drinkTaps.isEmpty ?? true) ? "Quiet one." : "Cube's had enough."
    }
}

// The roll result: pips + rule, sized to be read across a dark table.
private struct RollResultView: View {
    let rule: PartyRule
    let roll: RollEvent

    @Environment(\.palette) private var palette

    @State private var scale: CGFloat = 0.86
    @State private var flash: Double = 0

    private var faceColor: Color {
        Mode.fromFaceIndex(rule.pips - 1)?.color ?? Theme.party
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(faceColor.opacity(flash))

            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(faceColor.opacity(0.55), lineWidth: 2)
                    .overlay {
                        PipsView(count: rule.pips, color: faceColor)
                            .padding(13)
                    }
                    .frame(width: 76, height: 76)

                Text(rule.name.uppercased())
                    .font(.system(size: 54, weight: .black))
                    .kerning(-1)
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(rule.detail)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 22)
            .scaleEffect(scale)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear { animateIn() }
        .onChange(of: roll.id) { _, _ in animateIn() }
    }

    private func animateIn() {
        scale = 0.86
        flash = 0.22
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { scale = 1 }
        withAnimation(.easeOut(duration: 0.9)) { flash = 0 }
    }
}

// Neutral documentation, never a scoreboard: no records, no streaks, no praise.
private struct DrinkCounterView: View {
    @Environment(\.palette) private var palette

    let count: Int
    let pulse: Int
    let promptsDrink: Bool

    @State private var bump: CGFloat = 1

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .contentTransition(.numericText())
                    .scaleEffect(bump)
                Text(count == 1 ? "drink" : "drinks")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.inkSecondary)
                Spacer()
                Text("double-tap = +1")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.inkMuted)
            }
            Text(promptsDrink
                 ? "Double-tap the cube when you drink."
                 : "The cube's counting for the whole table.")
                .font(.system(size: 12.5))
                .foregroundStyle(promptsDrink ? Theme.party : palette.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card(cornerRadius: 20)
        .onChange(of: pulse) { _, _ in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bump = 1.18 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = 1 }
            }
        }
        .animation(.spring(duration: 0.3), value: count)
    }
}

// The deck, spelled out. Same shape as the day tab's face list so the two
// halves of the app read as one product.
struct RuleDeckCard: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE DECK · \(RuleDeck.name.uppercased())")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)

            VStack(spacing: 12) {
                ForEach(RuleDeck.rules) { rule in
                    HStack(spacing: 12) {
                        DieFaceView(mode: Mode.fromFaceIndex(rule.pips - 1), size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.ink)
                            Text(rule.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .card(cornerRadius: 20)
        }
    }
}
