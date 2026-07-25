import SwiftUI

@main
struct TodayCubeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store: AppStore
    @StateObject private var ble: CubeBLEManager

    init() {
        let store = AppStore()
        let ble = CubeBLEManager()
        ble.onFace = { mode in
            Task { @MainActor in store.setTodayMode(mode) }
        }
        _store = StateObject(wrappedValue: store)
        _ble = StateObject(wrappedValue: ble)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(ble)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.rollForwardToToday() }
        }
    }
}
