import Foundation
import CoreBluetooth

/// One proximity-pairing advert seen from one peripheral.
public struct BLEObservation: Sendable, Equatable {
    public let peripheralID: UUID
    public let message: ProximityMessage
    public let rssi: Int
    public let date: Date
}

/// Continuously scans for Apple proximity-pairing adverts.
///
/// Delivers on the main queue so downstream state stays single-threaded.
/// Duplicate adverts are allowed through on purpose: RSSI has to update live
/// for the proximity finder, and the lid counter must be seen as it changes.
@MainActor
public final class BLEScanner: NSObject {
    public enum State: Equatable, Sendable {
        case idle, unsupported, unauthorized, poweredOff, scanning
    }

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    public var onObservation: ((BLEObservation) -> Void)?
    public var onStateChange: ((State) -> Void)?
    /// Fires only when a device's lid-open counter actually advances.
    public var onLidOpened: ((BLEObservation) -> Void)?

    private var central: CBCentralManager?
    /// Keyed by peripheral, never by model: two people with the same AirPods
    /// model in one room would otherwise share a counter and fire phantom
    /// lid-open events at each other.
    private var lastLidCounter: [UUID: Int] = [:]
    /// Suppresses repeat HUDs from advert bursts after a single lid open.
    private var lastLidFire: [UUID: Date] = [:]
    private let lidDebounce: TimeInterval = 6
    /// A lid opening across the street is not yours. Adverts weaker than this
    /// never trigger the HUD, though they still appear in `watch`.
    public var lidRSSIFloor = -80

    public override init() { super.init() }

    public func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func stop() {
        central?.stopScan()
        central = nil
        state = .idle
    }

    private func beginScan() {
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        state = .scanning
    }
}

/// CoreBluetooth is constructed with `queue: .main`, so every delegate callback
/// already arrives on the main thread. The methods are `nonisolated` to satisfy
/// the protocol and re-enter the actor via `assumeIsolated`, which is sound only
/// because of that queue choice - do not change the queue without revisiting this.
extension BLEScanner: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        MainActor.assumeIsolated { self.handleStateChange(c) }
    }

    public nonisolated func centralManager(_ c: CBCentralManager,
                                           didDiscover p: CBPeripheral,
                                           advertisementData d: [String: Any],
                                           rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { self.handleDiscovery(p, d, RSSI) }
    }
}

extension BLEScanner {
    private func handleStateChange(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: beginScan()
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        case .poweredOff: state = .poweredOff
        default: state = .idle
        }
    }

    private func handleDiscovery(_ p: CBPeripheral,
                                 _ d: [String: Any],
                                 _ RSSI: NSNumber) {
        guard let raw = d[CBAdvertisementDataManufacturerDataKey] as? Data,
              let msg = ProximityMessage.parse(manufacturerData: raw)
        else { return }

        // 127 is CoreBluetooth's "unavailable" sentinel, not a real reading.
        let rssi = RSSI.intValue
        let obs = BLEObservation(peripheralID: p.identifier, message: msg,
                                 rssi: rssi == 127 ? -127 : rssi, date: Date())
        onObservation?(obs)

        let key = p.identifier
        let previous = lastLidCounter[key]
        lastLidCounter[key] = msg.lidCounter
        guard let previous, previous != msg.lidCounter else { return }
        guard obs.rssi >= lidRSSIFloor else { return }

        let now = Date()
        if let last = lastLidFire[key], now.timeIntervalSince(last) < lidDebounce { return }
        lastLidFire[key] = now
        onLidOpened?(obs)
    }
}
