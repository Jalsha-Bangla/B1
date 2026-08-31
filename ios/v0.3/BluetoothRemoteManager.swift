import Foundation
import CoreBluetooth
import Combine

final class BluetoothRemoteManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "7B3E1001-2F9A-4E2A-9A6B-1C6C0F9B1001")
    static let commandUUID = CBUUID(string: "7B3E1002-2F9A-4E2A-9A6B-1C6C0F9B1001")

    @Published var statusText = "Starting Bluetooth…"
    @Published var isReady = false

    private let rememberedPeripheralKey = "B1RememberedPeripheralIdentifier"
    private let restorationIdentifier = "com.fks.b1remote.ios.central"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    private var reconnectWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var discoveryTimeoutWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?

    private var reconnectAttempt = 0
    private var forceFreshScanNext = false

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationIdentifier]
        )
    }

    func reconnect() {
        reconnectAttempt = 0
        forceFreshScanNext = true
        cancelTransientWork()
        disconnectCurrentPeripheralIfNeeded()
        beginConnectionFlow()
    }

    func resumeAfterForeground() {
        guard central.state == .poweredOn else { return }
        if isReady, peripheral?.state == .connected, commandCharacteristic != nil {
            statusText = "B1 Connected"
            return
        }
        beginConnectionFlow()
    }

    func send(_ command: String) {
        guard
            let peripheral,
            peripheral.state == .connected,
            let characteristic = commandCharacteristic,
            let data = command.data(using: .utf8)
        else {
            markDisconnected("Reconnecting to B1…")
            scheduleReconnect(preferFreshScan: false, minimumDelay: 0.10)
            return
        }

        let type: CBCharacteristicWriteType
        if characteristic.properties.contains(.write) {
            type = .withResponse
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else {
            statusText = "Command channel is not writable"
            return
        }

        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func beginConnectionFlow() {
        guard central.state == .poweredOn else { return }
        cancelTransientWork()

        if let peripheral, peripheral.state == .connected {
            peripheral.delegate = self
            discoverRemoteService(on: peripheral)
            return
        }

        if !forceFreshScanNext, let remembered = rememberedPeripheral() {
            connect(to: remembered, label: "Reconnecting to B1…")
            return
        }

        forceFreshScanNext = false
        startScanning()
    }

    private func rememberedPeripheral() -> CBPeripheral? {
        guard
            let raw = UserDefaults.standard.string(forKey: rememberedPeripheralKey),
            let id = UUID(uuidString: raw)
        else { return nil }

        return central.retrievePeripherals(withIdentifiers: [id]).first
    }

    private func connect(to candidate: CBPeripheral, label: String) {
        central.stopScan()
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil

        if let current = peripheral,
           current.identifier != candidate.identifier,
           current.state == .connected || current.state == .connecting {
            central.cancelPeripheralConnection(current)
        }

        peripheral = candidate
        candidate.delegate = self
        commandCharacteristic = nil
        isReady = false
        statusText = label

        if candidate.state == .connected {
            discoverRemoteService(on: candidate)
            return
        }

        if candidate.state == .connecting { return }

        central.connect(candidate, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        armConnectionTimeout(for: candidate)
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }

        central.stopScan()
        markDisconnected("Searching for B1…")

        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.central.state == .poweredOn, !self.isReady else { return }
            self.central.stopScan()
            self.statusText = "B1 not found — retrying…"
            self.scheduleReconnect(preferFreshScan: true, minimumDelay: 0.50)
        }
        scanTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: item)
    }

    private func discoverRemoteService(on peripheral: CBPeripheral) {
        cancelConnectionTimeout()
        commandCharacteristic = nil
        isReady = false
        statusText = "Restoring B1 connection…"
        peripheral.discoverServices([Self.serviceUUID])
        armDiscoveryTimeout(for: peripheral)
    }

    private func scheduleReconnect(preferFreshScan: Bool, minimumDelay: TimeInterval? = nil) {
        reconnectWorkItem?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, 20)
        if preferFreshScan { forceFreshScanNext = true }

        let backoff: [TimeInterval] = [0.15, 0.30, 0.60, 1.0, 1.5, 2.0, 3.0, 5.0]
        let index = min(max(reconnectAttempt - 1, 0), backoff.count - 1)
        let delay = max(backoff[index], minimumDelay ?? 0)

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.central.state == .poweredOn else { return }
            self.beginConnectionFlow()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func armConnectionTimeout(for target: CBPeripheral) {
        cancelConnectionTimeout()
        let id = target.identifier
        let item = DispatchWorkItem { [weak self] in
            guard
                let self,
                let current = self.peripheral,
                current.identifier == id,
                !self.isReady,
                current.state != .connected
            else { return }

            self.statusText = "Connection timeout — rescanning…"
            self.central.cancelPeripheralConnection(current)
            self.forceFreshScanNext = true
            self.scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
        }
        connectionTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: item)
    }

    private func armDiscoveryTimeout(for target: CBPeripheral) {
        discoveryTimeoutWorkItem?.cancel()
        let id = target.identifier
        let item = DispatchWorkItem { [weak self] in
            guard
                let self,
                let current = self.peripheral,
                current.identifier == id,
                !self.isReady
            else { return }

            self.statusText = "B1 service timeout — recovering…"
            self.central.cancelPeripheralConnection(current)
            self.forceFreshScanNext = true
            self.scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
        }
        discoveryTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: item)
    }

    private func disconnectCurrentPeripheralIfNeeded() {
        guard let peripheral else { return }
        if peripheral.state == .connected || peripheral.state == .connecting {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func markDisconnected(_ text: String) {
        isReady = false
        commandCharacteristic = nil
        statusText = text
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }

    private func cancelTransientWork() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        discoveryTimeoutWorkItem?.cancel()
        discoveryTimeoutWorkItem = nil
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
    }

    private func handleConnectionLoss(_ peripheral: CBPeripheral, message: String) {
        cancelTransientWork()
        markDisconnected(message)
        self.peripheral = peripheral
        peripheral.delegate = self

        forceFreshScanNext = reconnectAttempt >= 2
        scheduleReconnect(preferFreshScan: forceFreshScanNext, minimumDelay: 0.10)
    }
}

extension BluetoothRemoteManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            reconnectAttempt = 0
            beginConnectionFlow()
        case .poweredOff:
            cancelTransientWork()
            markDisconnected("Bluetooth is Off")
        case .unauthorized:
            cancelTransientWork()
            markDisconnected("Bluetooth permission needed")
        case .unsupported:
            cancelTransientWork()
            markDisconnected("Bluetooth LE unsupported")
        case .resetting:
            cancelTransientWork()
            markDisconnected("Bluetooth resetting…")
        case .unknown:
            markDisconnected("Bluetooth state unknown")
        @unknown default:
            markDisconnected("Bluetooth unavailable")
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        guard
            let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
            let candidate = restored.first
        else { return }

        peripheral = candidate
        candidate.delegate = self
        UserDefaults.standard.set(candidate.identifier.uuidString, forKey: rememberedPeripheralKey)

        switch candidate.state {
        case .connected:
            discoverRemoteService(on: candidate)
        case .connecting:
            statusText = "Restoring B1 connection…"
            armConnectionTimeout(for: candidate)
        default:
            scheduleReconnect(preferFreshScan: false, minimumDelay: 0.10)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedPeripheralKey)
        reconnectAttempt = 0
        connect(to: peripheral, label: "Connecting to B1…")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelConnectionTimeout()
        reconnectAttempt = 0
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedPeripheralKey)
        self.peripheral = peripheral
        peripheral.delegate = self
        discoverRemoteService(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        handleConnectionLoss(peripheral, message: "Connection failed — recovering…")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        handleConnectionLoss(peripheral, message: "B1 disconnected — reconnecting…")
    }
}

extension BluetoothRemoteManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            statusText = "Service recovery: (error.localizedDescription)"
            central.cancelPeripheralConnection(peripheral)
            scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            statusText = "B1 service missing — rescanning…"
            central.cancelPeripheralConnection(peripheral)
            scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
            return
        }

        peripheral.discoverCharacteristics([Self.commandUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            statusText = "Channel recovery: (error.localizedDescription)"
            central.cancelPeripheralConnection(peripheral)
            scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.commandUUID }) else {
            statusText = "B1 command channel missing — rescanning…"
            central.cancelPeripheralConnection(peripheral)
            scheduleReconnect(preferFreshScan: true, minimumDelay: 0.20)
            return
        }

        discoveryTimeoutWorkItem?.cancel()
        discoveryTimeoutWorkItem = nil
        commandCharacteristic = characteristic
        reconnectAttempt = 0
        forceFreshScanNext = false
        isReady = true
        statusText = "B1 Connected"
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            statusText = "Command link interrupted — recovering…"
            isReady = false
            commandCharacteristic = nil
            central.cancelPeripheralConnection(peripheral)
            scheduleReconnect(preferFreshScan: false, minimumDelay: 0.10)
        } else if isReady {
            statusText = "B1 Connected"
        }
    }
}
