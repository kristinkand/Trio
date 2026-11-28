import CoreBluetooth

/// G7Direct's Bluetooth central, under its own restore identifier. watchOS keeps the connect to the sensor it left
/// pending after the reader stopped reading, and the sensor answered that instead of `WatchCGMHost`, which searched on
/// without pairing. Brought up at launch only to cancel what it still holds; it does nothing else.
final class RetiredReaderCentral: NSObject, CBCentralManagerDelegate {
    static let shared = RetiredReaderCentral()

    private var central: CBCentralManager?
    private var restored: [CBPeripheral] = []

    func release() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "org.nightscout.Trio.watchG7Reader"]
        )
    }

    func centralManager(_: CBCentralManager, willRestoreState dict: [String: Any]) {
        restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        guard !restored.isEmpty else { return }
        for peripheral in restored {
            central.cancelPeripheralConnection(peripheral)
        }
        WatchLogger.shared.info(.lifecycle, "Old watch reader's Bluetooth: \(restored.count) pending connection(s) cancelled")
        restored = []
    }
}
