// blescan.swift — proves macOS still delivers Apple 0x07 proximity-pairing adverts.
// Build: swiftc -O blescan.swift -o blescan && ./blescan
// Scans 20s. Exits 0 if any 0x07 packet was seen, 1 if none. See docs/PROTOCOL.md.

import Foundation
import CoreBluetooth

final class Scanner: NSObject, CBCentralManagerDelegate {
    var central: CBCentralManager!
    var appleSeen = 0, type07 = 0, total = 0
    func start() { central = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("state:", c.state.rawValue, "(5 = poweredOn)")
        if c.state == .poweredOn {
            c.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            print("scanning...")
        } else if c.state == .unauthorized {
            print("UNAUTHORIZED - Bluetooth TCC permission denied")
            exit(2)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData d: [String: Any], rssi: NSNumber) {
        total += 1
        guard let md = d[CBAdvertisementDataManufacturerDataKey] as? Data, md.count >= 2 else { return }
        let company = UInt16(md[0]) | (UInt16(md[1]) << 8)
        guard company == 0x004C else { return }
        appleSeen += 1
        let payload = md.dropFirst(2)
        guard let msgType = payload.first else { return }
        if msgType == 0x07 {
            type07 += 1
            if type07 <= 3 {
                print("*** PROXIMITY PAIRING (0x07) len=\(payload.count) rssi=\(rssi)")
                print("    bytes: \(payload.map { String(format: "%02x", $0) }.joined())")
            }
        }
    }
}

let s = Scanner(); s.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    print("\n=== RESULT after 20s ===")
    print("total adv packets:      \(s.total)")
    print("Apple (0x004C) packets: \(s.appleSeen)")
    print("type 0x07 (AirPods):    \(s.type07)")
    exit(s.type07 > 0 ? 0 : 1)
}
RunLoop.main.run()
