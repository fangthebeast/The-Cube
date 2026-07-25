import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: CubeBLEManager

    @State private var showOverride = false
    @State private var selectedLog: DayLog?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                todayCard
                if showOverride { overridePanel }
                if store.showNudge { nudge }
                gridSection
                statsRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIGHT NOW")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Theme.inkMuted)
            Text("Whichever face is up.")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                DieFaceView(mode: store.currentMode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayCardLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(store.currentMode?.displayName ?? "Waiting for a flip")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(ble.status == .connected ? Theme.accent : Theme.inkMuted)
                    .frame(width: 6, height: 6)
                Text(ble.status.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card()
        .onLongPressGesture(minimumDuration: 0.8) {
            withAnimation(.spring(duration: 0.35)) { showOverride.toggle() }
        }
    }

    // Hidden dev override (long-press the today card): stands in for the cube
    // if BLE flakes during a live demo.
    private var overridePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEV OVERRIDE")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Button {
                        store.setTodayMode(mode)
                    } label: {
                        DieFaceView(mode: mode, size: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Taps stand in for the cube while it's offline.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 20)
    }

    private var todayCardLabel: String {
        if store.currentMode != nil { return "Cube is resting on" }
        return ble.status == .connected ? "Cube connected" : "Cube not connected"
    }

    private var nudge: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text("Rest's been carrying the last few days. No rush — a Move day is sitting right here whenever it sounds good.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.accentSoft)
        )
    }

    // MARK: - Life grid

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 12 weeks")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.totalLogged) days logged")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.inkMuted)
            }
            LifeGridView(history: store.history, selectedLog: $selectedLog)
            if let selected = selectedLog {
                Text(detailText(for: selected))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
            }
            legend
        }
    }

    private func detailText(for log: DayLog) -> String {
        let dateStr = log.date.formatted(.dateTime.month(.abbreviated).day())
        let isToday = Calendar.current.isDateInToday(log.date)
        if isToday {
            return log.mode.map { "\(dateStr) · today, live on \($0.displayName)" } ?? "\(dateStr) · today, just starting"
        }
        return "\(dateStr) · \(log.mode?.displayName ?? "No log")"
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { mode in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(mode.color)
                        .frame(width: 14, height: 14)
                        .overlay(PipsView(count: mode.pipCount).frame(width: 11, height: 11))
                    Text(mode.displayName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(.top, 2)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(store.totalLogged)", label: "Total logged")
            statTile(value: "\(Int((store.restShare * 100).rounded()))%", label: "Rest, last 12wk")
            statTile(value: "\(store.unlockedModes.count)/6", label: "Accessories")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 16)
    }
}

// GitHub-contribution-style grid: 12 columns of 7 days, oldest top-left,
// filled column by column like the mockup.
struct LifeGridView: View {
    let history: [DayLog]
    @Binding var selectedLog: DayLog?

    @State private var pulsing = false

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
        .onAppear { pulsing = true }
    }

    private func cell(for log: DayLog, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(log.mode?.color ?? Theme.surfaceRecede)
            .overlay {
                if let mode = log.mode {
                    PipsView(count: mode.pipCount)
                        .padding(3)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(pulsing ? 0.35 : 1.0), lineWidth: 2)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture { selectedLog = log }
    }
}
