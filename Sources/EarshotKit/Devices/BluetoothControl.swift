import Foundation
import IOBluetooth

/// Connect/disconnect over the public IOBluetooth API.
///
/// Deliberately avoids the private `BluetoothManager.framework`, which rejects
/// unsigned clients (see docs/FEASIBILITY.md section 8). Everything here is
/// supported API, which keeps notarization simple.
public enum BluetoothControl {

    public struct PairedDevice: Sendable {
        public let address: String
        public let name: String
        public let isConnected: Bool
    }

    public static func pairedDevices() -> [PairedDevice] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.map {
            PairedDevice(address: normalize($0.addressString ?? ""),
                         name: $0.name ?? "Unknown",
                         isConnected: $0.isConnected())
        }
    }

    /// IOBluetooth uses `-` separators, system_profiler uses `:`.
    /// Everything inside Earshot is normalized to lowercase colon form.
    public static func normalize(_ address: String) -> String {
        address.replacingOccurrences(of: "-", with: ":").lowercased()
    }

    static func device(matching address: String) -> IOBluetoothDevice? {
        let target = normalize(address)
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        return list.first { normalize($0.addressString ?? "") == target }
    }

    public static func device(named name: String) -> IOBluetoothDevice? {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let lower = name.lowercased()
        return list.first { ($0.name ?? "").lowercased() == lower }
            ?? list.first { ($0.name ?? "").lowercased().contains(lower) }
    }

    @discardableResult
    public static func connect(address: String) -> Bool {
        guard let d = device(matching: address) else { return false }
        return d.openConnection() == kIOReturnSuccess
    }

    @discardableResult
    public static func disconnect(address: String) -> Bool {
        guard let d = device(matching: address) else { return false }
        return d.closeConnection() == kIOReturnSuccess
    }

    @discardableResult
    public static func toggle(address: String) -> Bool {
        guard let d = device(matching: address) else { return false }
        return d.isConnected() ? disconnect(address: address) : connect(address: address)
    }
}
