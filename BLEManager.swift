import Foundation
import CoreBluetooth
import Observation

enum ConnectionState: String {
    case idle, scanning, connecting, connected, disconnecting
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var isConnectable: Bool?
}

struct CharacteristicInfo: Identifiable {
    let id = UUID()
    let characteristic: CBCharacteristic
    var value: Data?
    var isNotifying = false
    var readPending = false
    var subscriptionPending = false
    var error: String?

    var uuid: String { characteristic.uuid.uuidString }
    var canRead: Bool { characteristic.properties.contains(.read) }
    var canSubscribe: Bool {
        !characteristic.properties.intersection([.notify, .indicate]).isEmpty
    }
    var propertyNames: String {
        let names: [(CBCharacteristicProperties, String)] = [
            (.read, "Read"), (.write, "Write"),
            (.writeWithoutResponse, "Write without response"),
            (.notify, "Notify"), (.indicate, "Indicate"),
            (.broadcast, "Broadcast"), (.extendedProperties, "Extended properties"),
            (.notifyEncryptionRequired, "Encrypted notify"),
            (.indicateEncryptionRequired, "Encrypted indicate")
        ]
        return names.filter { characteristic.properties.contains($0.0) }
            .map { $0.1 }.joined(separator: ", ")
    }
    var hexValue: String {
        guard let value else { return "No value received" }
        return value.isEmpty ? "(empty value)" : value.map {
            String(format: "%02X", $0)
        }.joined(separator: " ")
    }
    var decimalValue: String? {
        guard let value, !value.isEmpty, value.count <= 8 else { return nil }
        let number = value.enumerated().reduce(UInt64(0)) { result, pair in
            result | (UInt64(pair.element) << (8 * UInt64(pair.offset)))
        }
        return String(number)
    }
    var textValue: String? {
        guard let value else { return nil }
        return String(data: value, encoding: .utf8)
    }
}

struct ServiceInfo: Identifiable {
    let id = UUID()
    let service: CBService
    var characteristics: [CharacteristicInfo] = []
    var isDiscovering = true
    var error: String?
    var uuid: String { service.uuid.uuidString }
    var name: String? { BLEConstants.serviceName(for: service.uuid) }
}

@Observable
final class BLEManager: NSObject {
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var connectionState: ConnectionState = .idle
    private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    private(set) var connectedName: String?
    private(set) var services: [ServiceInfo] = []
    private(set) var isDiscoveringServices = false
    private(set) var lastError: String?
    private(set) var events: [String] = []

    @ObservationIgnored private var centralManager: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var connectionTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    var bluetoothStatus: String {
        switch bluetoothState {
        case .unknown: return "Bluetooth status pending"
        case .resetting: return "Bluetooth resetting"
        case .unsupported: return "BLE unavailable on this device"
        case .unauthorized: return "Bluetooth permission denied - check Settings"
        case .poweredOff: return "Bluetooth is off"
        case .poweredOn: return "Bluetooth ready"
        @unknown default: return "Unknown Bluetooth state"
        }
    }

    func startScanning() {
        guard bluetoothState == .poweredOn, connectionState == .idle else { return }
        lastError = nil
        discoveredPeripherals = []
        peripherals = [:]
        services = []
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: BLEConstants.scanServiceUUIDs)
        log("Scanning for BLE peripherals")
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.scanDuration,
                                        repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .idle
            log("Scan stopped")
        }
    }

    func connect(to device: DiscoveredPeripheral) {
        guard bluetoothState == .poweredOn,
              connectionState == .idle || connectionState == .scanning,
              device.isConnectable != false,
              let candidate = peripherals[device.id] else { return }
        stopScanning()
        lastError = nil
        services = []
        peripheral = candidate
        connectedName = device.name
        candidate.delegate = self
        connectionState = .connecting
        centralManager.connect(candidate, options: nil)
        log("Connecting to \(device.name)")
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.connectionTimeout,
                                               repeats: false) { [weak self] _ in
            guard let self, self.connectionState == .connecting else { return }
            self.report("Connection timed out. Check that the board is advertising and available.")
            self.disconnect()
        }
    }

    func disconnect() {
        guard let peripheral,
              connectionState == .connecting || connectionState == .connected else { return }
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(peripheral)
        log("Cancelling connection")
    }

    func read(_ id: UUID) {
        guard connectionState == .connected, let peripheral,
              let (s, c) = location(of: id) else { return }
        let item = services[s].characteristics[c]
        guard item.canRead, !item.readPending else { return }
        services[s].characteristics[c].error = nil
        services[s].characteristics[c].readPending = true
        peripheral.readValue(for: item.characteristic)
    }

    func toggleSubscription(_ id: UUID) {
        guard connectionState == .connected, let peripheral,
              let (s, c) = location(of: id) else { return }
        let item = services[s].characteristics[c]
        guard item.canSubscribe, !item.subscriptionPending else { return }
        services[s].characteristics[c].error = nil
        services[s].characteristics[c].subscriptionPending = true
        peripheral.setNotifyValue(!item.isNotifying, for: item.characteristic)
    }

    private func location(of id: UUID) -> (Int, Int)? {
        for s in services.indices {
            if let c = services[s].characteristics.firstIndex(where: { $0.id == id }) {
                return (s, c)
            }
        }
        return nil
    }

    private func location(of characteristic: CBCharacteristic) -> (Int, Int)? {
        for s in services.indices {
            if let c = services[s].characteristics.firstIndex(where: {
                $0.characteristic === characteristic
            }) { return (s, c) }
        }
        return nil
    }

    private func clearConnection() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        peripheral?.delegate = nil
        peripheral = nil
        connectedName = nil
        services = []
        isDiscoveringServices = false
        connectionState = .idle
    }

    private func report(_ message: String) {
        lastError = message
        log(message)
    }

    private func log(_ message: String) {
        events.insert(message, at: 0)
        if events.count > BLEConstants.maximumLogEntries { events.removeLast() }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        log(bluetoothStatus)
        if central.state != .poweredOn {
            stopScanning()
            clearConnection()
            peripherals = [:]
            discoveredPeripherals = []
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard connectionState == .scanning else { return }
        peripherals[peripheral.identifier] = peripheral
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed peripheral"
        let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let device = DiscoveredPeripheral(
            id: peripheral.identifier, name: name, rssi: RSSI.intValue,
            advertisedServices: uuids.map { $0.uuidString },
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        )
        if let index = discoveredPeripherals.firstIndex(where: { $0.id == device.id }) {
            discoveredPeripherals[index] = device
        } else {
            discoveredPeripherals.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        if connectionState == .disconnecting {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard connectionState == .connecting else { return }
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionState = .connected
        log("Connected; discovering services")
        isDiscoveringServices = true
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard self.peripheral === peripheral else { return }
        let wasCancelling = connectionState == .disconnecting
        clearConnection()
        if wasCancelling { log("Connection cancelled") }
        else { report("Connection failed: \(error?.localizedDescription ?? "Unknown error")") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard self.peripheral === peripheral else { return }
        clearConnection()
        if let error { report("Disconnected: \(error.localizedDescription)") }
        else { log("Disconnected") }
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral, connectionState == .connected else { return }
        isDiscoveringServices = false
        if let error { report("Service discovery failed: \(error.localizedDescription)"); return }
        services = (peripheral.services ?? []).map { ServiceInfo(service: $0) }
        log("Discovered \(services.count) services")
        for item in services {
            peripheral.discoverCharacteristics(nil, for: item.service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard self.peripheral === peripheral, connectionState == .connected,
              let index = services.firstIndex(where: { $0.service === service }) else { return }
        services[index].isDiscovering = false
        if let error {
            services[index].error = error.localizedDescription
            report("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        services[index].characteristics = (service.characteristics ?? []).map {
            CharacteristicInfo(characteristic: $0, value: $0.value, isNotifying: $0.isNotifying)
        }
        log("Discovered \(services[index].characteristics.count) characteristics for \(service.uuid.uuidString)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard self.peripheral === peripheral, connectionState == .connected,
              let (s, c) = location(of: characteristic) else { return }
        services[s].characteristics[c].readPending = false
        if let error {
            services[s].characteristics[c].error = error.localizedDescription
            report("Value update failed: \(error.localizedDescription)")
        } else {
            services[s].characteristics[c].value = characteristic.value
            services[s].characteristics[c].error = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, connectionState == .connected,
              let (s, c) = location(of: characteristic) else { return }
        services[s].characteristics[c].subscriptionPending = false
        services[s].characteristics[c].isNotifying = characteristic.isNotifying
        services[s].characteristics[c].error = error?.localizedDescription
        if let error { report("Subscription failed: \(error.localizedDescription)") }
        else { log("\(characteristic.uuid.uuidString): updates \(characteristic.isNotifying ? "on" : "off")") }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard self.peripheral === peripheral, connectionState == .connected else { return }
        services = []
        isDiscoveringServices = true
        log("Services changed; rediscovering")
        peripheral.discoverServices(nil)
    }
}
