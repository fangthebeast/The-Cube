import CoreBluetooth
import Foundation

// BLE central: scans for the cube, subscribes to the face + event
// characteristics, and writes LED colours back. Reconnects automatically.
final class CubeBLEManager: NSObject, ObservableObject {
    // ⚠️ PLACEHOLDER UUIDs — one-line swap each once firmware UUIDs are final.
    // These are the ESP32 Arduino BLE example defaults, so if the firmware
    // starts from that template the service may already match.
    static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let faceCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    static let eventCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A9")
    static let ledCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AA")

    // Event char payloads.
    private static let eventRollSettled: UInt8 = 0x01
    private static let eventDoubleTap: UInt8 = 0x02

    enum Status: Equatable {
        case bluetoothOff, scanning, connected

        var label: String {
            switch self {
            case .bluetoothOff: return "Bluetooth is off"
            case .scanning: return "Looking for your cube…"
            case .connected: return "Cube connected"
            }
        }
    }

    @Published private(set) var status: Status = .scanning

    // Wired up in WorkHardPlayHardCubeApp.
    var onFace: ((Mode) -> Void)?
    var onRollSettled: ((Mode?) -> Void)?
    var onDoubleTap: (() -> Void)?
    var onConnect: (() -> Void)?

    // Firmware fallback: with no roll-settled events, infer a roll app-side —
    // ≥2 face changes within 2s followed by ≥1s on one face. Flip this off
    // once the real event lands.
    var inferRollsFromFaceChanges = true

    private var central: CBCentralManager!
    private var cube: CBPeripheral?
    private var ledCharacteristic: CBCharacteristic?
    private var pendingLED: UInt8?

    // Roll inference bookkeeping.
    private var recentFaceChanges: [Date] = []
    private var settleWorkItem: DispatchWorkItem?
    private var sawRealRollEvent = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - LED

    func writeLED(_ command: LEDCommand) {
        guard let cube, let characteristic = ledCharacteristic else {
            pendingLED = command.rawValue     // replayed once the char shows up
            return
        }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        cube.writeValue(Data([command.rawValue]), for: characteristic, type: type)
    }

    // MARK: - Scanning

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        status = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    // MARK: - Roll inference

    private func noteFaceChange(_ mode: Mode) {
        guard inferRollsFromFaceChanges, !sawRealRollEvent else { return }
        let now = Date()
        recentFaceChanges.append(now)
        recentFaceChanges.removeAll { now.timeIntervalSince($0) > 2 }

        settleWorkItem?.cancel()
        guard recentFaceChanges.count >= 2 else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recentFaceChanges.removeAll()
            self.onRollSettled?(mode)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}

extension CubeBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        default:
            status = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        cube = peripheral
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        teardown()
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        teardown()
        startScanning()
    }

    private func teardown() {
        cube = nil
        ledCharacteristic = nil
        recentFaceChanges.removeAll()
        settleWorkItem?.cancel()
    }
}

extension CubeBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics(
            [Self.faceCharacteristicUUID, Self.eventCharacteristicUUID, Self.ledCharacteristicUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.faceCharacteristicUUID:
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            case Self.eventCharacteristicUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.ledCharacteristicUUID:
                ledCharacteristic = characteristic
                if let pending = pendingLED, let command = LEDCommand(rawValue: pending) {
                    pendingLED = nil
                    writeLED(command)
                }
            default:
                break
            }
        }
        onConnect?()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let byte = characteristic.value?.first else { return }

        switch characteristic.uuid {
        case Self.faceCharacteristicUUID:
            guard let mode = Mode.fromFaceIndex(Int(byte)) else { return }
            onFace?(mode)
            noteFaceChange(mode)

        case Self.eventCharacteristicUUID:
            switch byte {
            case Self.eventRollSettled:
                sawRealRollEvent = true      // real events win; stop inferring
                settleWorkItem?.cancel()
                onRollSettled?(nil)
            case Self.eventDoubleTap:
                onDoubleTap?()
            default:
                break
            }

        default:
            break
        }
    }
}
