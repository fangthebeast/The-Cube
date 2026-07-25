import SwiftUI

// Triple-tap any screen title to get here. Every cube input has a button, so a
// demo never depends on live BLE working in the room.
struct DevPanelView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager
    @EnvironmentObject private var ui: UIState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEV PANEL")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(palette.inkMuted)
                    Text("Stand in for the cube.")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(palette.ink)
                }

                statusBlock

                section("CUBE EVENTS") {
                    HStack(spacing: 10) {
                        smallButton("Roll", tint: Theme.party) { store.registerRoll(face: Mode.allCases.randomElement()) }
                        smallButton("Double-tap", tint: Theme.party) { store.logDrink() }
                    }
                    Text("Face up")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.inkMuted)
                    HStack(spacing: 8) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Button {
                                store.setFace(mode)
                            } label: {
                                DieFaceView(mode: mode, size: 44)
                                    .overlay {
                                        if store.currentFace == mode {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(palette.ink, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(Mode.allCases.map { "\($0.pipCount) \($0.displayName)" }.joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.inkMuted)
                }

                section("PHASE") {
                    HStack(spacing: 10) {
                        smallButton("Seed demo night", tint: palette.accent) { store.seedDemoNight() }
                        smallButton("Advance to morning", tint: palette.accent) { store.advanceToMorning() }
                    }
                    HStack(spacing: 10) {
                        smallButton("+1 hour", tint: palette.accent) { store.skipHour() }
                        smallButton("Force debt to 0", tint: palette.accent) { store.forceClearDebt() }
                    }
                    smallButton("Reset to idle", tint: palette.inkSecondary) { store.resetToIdle() }
                }

                section("LED") {
                    Text("App wants: \(ledLabel(store.currentLED)) — written on every change, debounced.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkSecondary)
                    smallButton("Resend LED to cube", tint: palette.inkSecondary) { store.resendLED() }
                }

                BigButton(title: "Done", tint: palette.accent) { ui.showDevPanel = false }
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(palette.paper.ignoresSafeArea())
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("BLE", ble.status.label)
            row("Phase", phaseLabel)
            row("Face up", store.currentFace?.displayName ?? "—")
            if store.recoveryDay != nil {
                row("Debt", String(format: "%.1f", store.debtRemaining))
            }
            row("Roll inference", ble.inferRollsFromFaceChanges ? "on (firmware fallback)" : "off")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 18)
    }

    private var phaseLabel: String {
        switch store.phase {
        case .idle: return "idle"
        case .party(let s): return "party · \(s.drinkTaps.count) drinks, \(s.rolls.count) rolls"
        case .recovery(let d): return d.clearedAt == nil ? "recovery" : "recovery · cleared"
        }
    }

    private func ledLabel(_ command: LEDCommand) -> String {
        switch command {
        case .off: return "off (0)"
        case .red: return "red (1)"
        case .yellow: return "yellow (2)"
        case .green: return "green (3)"
        case .partyPulse: return "blue pulse (4)"
        case .celebrate: return "celebration (5)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkMuted)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.ink)
            Spacer()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(palette.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}
