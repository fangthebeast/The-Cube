import SwiftUI

@main
struct WorkHardPlayHardCubeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store: AppStore
    @StateObject private var ble: CubeBLEManager
    @StateObject private var ui = UIState()

    init() {
        let store = AppStore()
        let ble = CubeBLEManager()

        ble.onFace = { mode in
            Task { @MainActor in store.setFace(mode) }
        }
        ble.onRollSettled = { face in
            Task { @MainActor in store.registerRoll(face: face) }
        }
        ble.onDoubleTap = {
            Task { @MainActor in store.registerDrinkTap() }
        }
        ble.onConnect = {
            Task { @MainActor in store.resendLED() }
        }
        // The cube only learns about colour changes through here.
        store.onLED = { [weak ble] command in
            ble?.writeLED(command)
        }

        _store = StateObject(wrappedValue: store)
        _ble = StateObject(wrappedValue: ble)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(ble)
                .environmentObject(ui)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.rollForwardToToday()
                store.applyDecay()      // bodies recover while the app is closed
            }
        }
    }
}
