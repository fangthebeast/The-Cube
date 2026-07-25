import SwiftUI

// UI-only state that outlives a single view: which tab is up, whether the
// hidden dev panel is showing.
enum Tab {
    case tonight, today

    // Each half of the app gets its own time of day.
    var palette: Palette { self == .tonight ? .night : .day }
}

@MainActor
final class UIState: ObservableObject {
    @Published var showDevPanel = false
    @Published var tab: Tab = .tonight
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ui: UIState

    private var tab: Tab { ui.tab }
    private var palette: Palette { ui.tab.palette }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch ui.tab {
                case .tonight: TonightView()
                case .today: RecoveryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background {
            ZStack {
                palette.paper
                AmbientGlow()
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.35), value: ui.tab)
        .sheet(isPresented: $ui.showDevPanel) { DevPanelView() }
        // Starting a night is a mode switch — follow it. Ending one is not:
        // the summary sheet lives on Tonight and hands over to Today itself.
        .onChange(of: store.isPartying) { _, partying in
            if partying { ui.tab = .tonight }
        }
        // Outermost on purpose: a sheet only inherits the environment of the
        // view it hangs off, so setting this any deeper leaves sheets on the
        // wrong palette.
        .environment(\.palette, palette)
        // Drives the status bar: light clock at night, dark clock on paper.
        .preferredColorScheme(palette.colorScheme)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.tonight, label: "Tonight", tint: Theme.party) {
                Image(systemName: "die.face.5")
                    .font(.system(size: 17, weight: .medium))
            }
            tabButton(.today, label: "Today", tint: Palette.day.accent) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().frame(width: 4, height: 4))
            }
        }
        .background(palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private func tabButton<Icon: View>(_ target: Tab, label: String, tint: Color,
                                       @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            ui.tab = target
        } label: {
            VStack(spacing: 4) {
                icon()
                    .overlay(alignment: .topTrailing) {
                        if let dot = liveDot(for: target) {
                            Circle()
                                .fill(dot)
                                .frame(width: 6, height: 6)
                                .offset(x: 7, y: -3)
                        }
                    }
                Text(label)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .foregroundStyle(tab == target ? tint : palette.inkMuted)
        }
        .buttonStyle(.plain)
    }

    // A small dot on the tab that has something live going on.
    private func liveDot(for target: Tab) -> Color? {
        switch target {
        case .tonight:
            return store.isPartying ? Theme.party : nil
        case .today:
            guard let day = store.recoveryDay, day.clearedAt == nil else { return nil }
            return store.band.color
        }
    }
}
