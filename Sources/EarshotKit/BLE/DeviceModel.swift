import Foundation

/// Apple product identifiers as they appear in the proximity-pairing advert.
///
/// Three entries are confirmed against hardware on the development machine
/// (see `docs/PROTOCOL.md`); the rest are community-documented. Unknown ids
/// degrade to a readable hex name rather than being dropped, because a new
/// AirPods revision should still show a battery level.
public struct DeviceModel: Sendable, Hashable {
    public let id: UInt16
    public let name: String
    public let hasCase: Bool
    public let isSingleBattery: Bool

    public init(id: UInt16, name: String, hasCase: Bool = true, isSingleBattery: Bool = false) {
        self.id = id
        self.name = name
        self.hasCase = hasCase
        self.isSingleBattery = isSingleBattery
    }

    private static let known: [UInt16: DeviceModel] = {
        var m: [UInt16: DeviceModel] = [:]
        func add(_ id: UInt16, _ name: String, hasCase: Bool = true, single: Bool = false) {
            m[id] = DeviceModel(id: id, name: name, hasCase: hasCase, isSingleBattery: single)
        }
        add(0x2002, "AirPods")
        add(0x200F, "AirPods (2nd generation)")          // confirmed on-device
        add(0x2013, "AirPods (3rd generation)")
        add(0x2014, "AirPods (3rd generation)")
        add(0x2019, "AirPods (4th generation)")
        add(0x201B, "AirPods (4th generation, ANC)")
        add(0x200E, "AirPods Pro")
        add(0x2024, "AirPods Pro (2nd generation)")      // confirmed on-device
        add(0x2026, "AirPods Pro (2nd generation)")
        add(0x2027, "AirPods Pro (3rd generation)")      // confirmed on-device
        add(0x200A, "AirPods Max", hasCase: false, single: true)
        add(0x201F, "AirPods Max (USB-C)", hasCase: false, single: true)
        add(0x2003, "Powerbeats3", hasCase: false, single: true)
        add(0x200B, "Powerbeats Pro")
        add(0x200D, "Powerbeats4", hasCase: false, single: true)
        add(0x2005, "BeatsX", hasCase: false, single: true)
        add(0x2006, "Beats Solo3", hasCase: false, single: true)
        add(0x2009, "Beats Studio3", hasCase: false, single: true)
        add(0x200C, "Beats Solo Pro", hasCase: false, single: true)
        add(0x2010, "Beats Flex", hasCase: false, single: true)
        add(0x2011, "Beats Studio Buds")
        add(0x2012, "Beats Fit Pro")
        add(0x2016, "Beats Studio Buds+")
        return m
    }()

    public static func lookup(_ id: UInt16) -> DeviceModel {
        known[id] ?? DeviceModel(id: id, name: String(format: "Apple headphones (0x%04X)", id))
    }
}
