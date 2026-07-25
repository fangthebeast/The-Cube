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
            Task { @MainActor in store.logDrink() }
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
                .onOpenURL { url in
                    Task { @MainActor in route(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.rollForwardToToday()
                store.applyDecay()      // bodies recover while the app is closed
            }
        }
    }

    // Lets a serial bridge stand in for the cube in the simulator, where
    // there's no CoreBluetooth. Deliberately routes to the same handlers the
    // BLE notifications do — no second code path to keep in sync.
    //
    //   cube://face/4   pips 1–6, converted at this boundary like the face char
    //   cube://roll     roll-settled, lands on whatever face is current
    //   cube://drink    double-tap
    @MainActor
    private func route(_ url: URL) {
        guard url.scheme == "cube" else { return }
        switch url.host() {
        case "face":
            guard let pips = Int(url.lastPathComponent),
                  let mode = Mode.fromFaceIndex(pips - 1) else { return }
            store.setFace(mode)
        case "roll":
            store.registerRoll(face: nil)
        case "drink":
            store.logDrink()
        default:
            break
        }
    }
}
