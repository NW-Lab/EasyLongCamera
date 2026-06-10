import CoreBluetooth
import Combine

// M5Atom LiteのカスタムGATT UUID（Arduino側と一致させること）
let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-123456789012")
let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789013")

enum BLEConnectionState {
    case scanning
    case connecting
    case connected
    case disconnected
}

class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var isButtonPressed: Bool = false

    // ボタン押下イベントをCameraManagerに伝えるクロージャ
    var onButtonPressed: (() -> Void)?
    var onButtonReleased: (() -> Void)?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        print("BLE: Scanning for M5Atom Shutter...")
    }

    func stopScanning() {
        centralManager.stopScan()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("BLE: Powered ON - starting scan")
            startScanning()
        case .poweredOff:
            connectionState = .disconnected
            print("BLE: Powered OFF")
        default:
            print("BLE: State = \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("BLE: Discovered \(peripheral.name ?? "unknown")")
        self.peripheral = peripheral
        centralManager.stopScan()
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BLE: Connected to \(peripheral.name ?? "unknown")")
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("BLE: Disconnected - restarting scan")
        self.peripheral = nil
        self.characteristic = nil
        connectionState = .disconnected
        // 切断後に自動再スキャン
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == characteristicUUID {
                self.characteristic = char
                // Notifyを購読する
                peripheral.setNotifyValue(true, for: char)
                print("BLE: Subscribed to shutter characteristic")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value, let byte = data.first else { return }

        DispatchQueue.main.async {
            if byte == 0x01 {
                // ボタン押下
                self.isButtonPressed = true
                self.onButtonPressed?()
                print("BLE: Button PRESSED")
            } else {
                // ボタン離す
                self.isButtonPressed = false
                self.onButtonReleased?()
                print("BLE: Button RELEASED")
            }
        }
    }
}
