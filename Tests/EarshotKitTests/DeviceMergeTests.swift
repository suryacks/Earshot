import XCTest
@testable import EarshotKit

final class DeviceMergeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func advert(model: UInt16, battery: UInt8, rssi: Int,
                        age: TimeInterval = 0, lid: UInt8 = 1,
                        peripheral: UUID = UUID()) -> BLEObservation {
        let payload = [0x01, UInt8(model & 0xFF), UInt8(model >> 8), 0x2b,
                       battery, 0x8f, lid, 0x00, 0x09] + [UInt8](repeating: 0, count: 16)
        let data = Data([0x4C, 0x00, 0x07, 0x19] + payload)
        let msg = ProximityMessage.parse(manufacturerData: data)!
        return BLEObservation(peripheralID: peripheral, message: msg, rssi: rssi,
                              date: now.addingTimeInterval(-age))
    }

    private func paired(_ name: String, address: String, product: UInt16,
                        left: Int? = nil, right: Int? = nil) -> DeviceState {
        var d = DeviceState(id: address, name: name)
        d.address = address
        d.productID = product
        d.isPaired = true
        d.left = left
        d.right = right
        return d
    }

    // MARK: - Source precedence

    /// Adverts round to 10%. Letting one overwrite a connected device's exact
    /// 86% with 80% would make the reading visibly jitter.
    func testConnectedDeviceKeepsPreciseLevelsOverAdvert() {
        let device = paired("AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027,
                            left: 86, right: 88)
        let out = DeviceMerge.merge(
            profiled: [device],
            adverts: [advert(model: 0x2027, battery: 0x88, rssi: -40)],
            connectedAddresses: ["aa:bb:cc:dd:ee:ff"],
            now: now)
        XCTAssertEqual(out[0].left, 86)
        XCTAssertEqual(out[0].right, 88)
        XCTAssertFalse(out[0].batteryFromAdvert)
    }

    /// ...but the advert's RSSI is still the freshest, for the finder.
    func testConnectedDeviceStillTakesAdvertRSSI() {
        let device = paired("AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027,
                            left: 86, right: 88)
        let out = DeviceMerge.merge(
            profiled: [device],
            adverts: [advert(model: 0x2027, battery: 0x88, rssi: -41)],
            connectedAddresses: ["aa:bb:cc:dd:ee:ff"],
            now: now)
        XCTAssertEqual(out[0].rssi, -41)
    }

    /// The whole point of the project: battery for a device in its case.
    func testDisconnectedDeviceGetsBatteryFromAdvert() {
        let device = paired("AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027)
        let out = DeviceMerge.merge(
            profiled: [device],
            adverts: [advert(model: 0x2027, battery: 0x77, rssi: -45)],
            connectedAddresses: [],
            now: now)
        XCTAssertEqual(out[0].left, 70)
        XCTAssertEqual(out[0].right, 70)
        XCTAssertTrue(out[0].batteryFromAdvert)
    }

    // MARK: - Identity

    /// Regression: adverts were keyed by model, so a neighbour's identical
    /// AirPods overwrote the user's battery on a last-write-wins basis.
    func testNeighbourWithSameModelDoesNotOverwriteOwnBattery() {
        let mine = paired("My AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027)
        let near = advert(model: 0x2027, battery: 0x99, rssi: -44)   // mine, close
        let far = advert(model: 0x2027, battery: 0x22, rssi: -95)    // theirs, far
        for adverts in [[near, far], [far, near]] {   // order must not matter
            let out = DeviceMerge.merge(profiled: [mine], adverts: adverts,
                                        connectedAddresses: [], now: now)
            XCTAssertEqual(out[0].left, 90, "nearest advert must win")
            XCTAssertEqual(out[0].rssi, -44)
        }
    }

    func testUnpairedDeviceIsNotPresentedAsOwn() {
        let out = DeviceMerge.merge(
            profiled: [],
            adverts: [advert(model: 0x2027, battery: 0x55, rssi: -70)],
            connectedAddresses: [], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].isPaired)
    }

    func testDuplicatePeripheralsOfSameModelCollapseToOneRow() {
        let a = advert(model: 0x2027, battery: 0x55, rssi: -70)
        let b = advert(model: 0x2027, battery: 0x55, rssi: -60)
        let out = DeviceMerge.merge(profiled: [], adverts: [a, b],
                                    connectedAddresses: [], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].rssi, -60, "nearest of the duplicates")
    }

    // MARK: - Staleness

    func testStaleAdvertIsIgnored() {
        let device = paired("AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027)
        let out = DeviceMerge.merge(
            profiled: [device],
            adverts: [advert(model: 0x2027, battery: 0x99, rssi: -44, age: 120)],
            connectedAddresses: [], now: now, ttl: 30)
        XCTAssertNil(out[0].left, "an advert from two minutes ago is not current state")
        XCTAssertFalse(out[0].batteryFromAdvert)
    }

    func testStaleUnpairedAdvertDisappearsEntirely() {
        let out = DeviceMerge.merge(
            profiled: [],
            adverts: [advert(model: 0x2027, battery: 0x99, rssi: -44, age: 120)],
            connectedAddresses: [], now: now, ttl: 30)
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - Connection state and ordering

    func testConnectionStateComesFromIOBluetoothNotProfiler() {
        var stale = paired("AirPods", address: "aa:bb:cc:dd:ee:ff", product: 0x2027)
        stale.isConnected = true          // profiler snapshot says connected
        let out = DeviceMerge.merge(profiled: [stale], adverts: [],
                                    connectedAddresses: [], now: now)
        XCTAssertFalse(out[0].isConnected, "live IOBluetooth state must win")
    }

    func testAddressComparisonIgnoresSeparatorAndCase() {
        let device = paired("AirPods", address: "AA-BB-CC-DD-EE-FF", product: 0x2027)
        let out = DeviceMerge.merge(profiled: [device], adverts: [],
                                    connectedAddresses: ["aa:bb:cc:dd:ee:ff"], now: now)
        XCTAssertTrue(out[0].isConnected)
    }

    func testOrderingPutsConnectedFirstThenPairedThenNearby() {
        var connected = paired("Zeta", address: "11:11:11:11:11:11", product: 0x2027)
        connected.isConnected = true
        let pairedIdle = paired("Alpha", address: "22:22:22:22:22:22", product: 0x200F)
        let out = DeviceMerge.merge(
            profiled: [pairedIdle, connected],
            adverts: [advert(model: 0x2024, battery: 0x55, rssi: -70)],
            connectedAddresses: ["11:11:11:11:11:11"], now: now)
        XCTAssertEqual(out.map(\.name), ["Zeta", "Alpha", "AirPods Pro (2nd generation)"])
    }

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertTrue(DeviceMerge.merge(profiled: [], adverts: [],
                                        connectedAddresses: [], now: now).isEmpty)
    }
}
