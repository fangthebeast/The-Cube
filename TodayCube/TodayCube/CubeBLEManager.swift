import CoreBluetooth
import Foundation

// BLE central: scans for the cube, subscribes to its face characteristic
// (single UInt8, 0–5 = face index), reconnects automatically on drops.
final class CubeBLEManager: NSObject, ObservableObject {
    // ⚠️ PLACEHOLDER UUIDs — one-line swap once firmware UUIDs are final.
    // These are the ESP32 Arduino BLE example defaults, so if the firmware
    // starts from that template they may already match.
    static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let faceCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    enum Status {
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

    // Wired up in TodayCubeApp to push face changes into the AppStore.
    var onFace: ((Mode) -> Void)?

    private var central: CBCentralManager!
    private var cube: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        status = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])
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
        cube = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cube = nil
        startScanning()
    }
}

extension CubeBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.faceCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.faceCharacteristicUUID }) else { return }
        peripheral.setNotifyValue(true, for: characteristic)
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let byte = characteristic.value?.first,
              let mode = Mode.fromFaceIndex(Int(byte)) else { return }
        onFace?(mode)
    }
}
