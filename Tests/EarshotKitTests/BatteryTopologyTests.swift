import XCTest
@testable import EarshotKit

/// Regression tests for a bug found against live hardware: a nearby AirPods Max
/// rendered as "L 0% · R 100% · case 0%". Single-cell devices populate both
/// nibbles but only one is meaningful, and they have no case at all.
final class BatteryTopologyTests: XCTestCase {

    /// model 0x200A (AirPods Max), battery byte 0x0A -> low nibble 10 -> 100%
    private let airPodsMax = "4c00" + "0719" + "010a202b0a8f110009" + String(repeating: "00", count: 16)

    func testSingleCellDeviceReportsOneBattery() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: airPodsMax))
        XCTAssertTrue(m.model.isSingleBattery)
        XCTAssertEqual(m.single, 100)
    }

    func testSingleCellDeviceHasNoLeftRightSplit() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: airPodsMax))
        XCTAssertNil(m.leftBattery, "a single-cell device must not report a left bud")
        XCTAssertNil(m.rightBattery, "a single-cell device must not report a right bud")
    }

    func testCaselessDeviceNeverReportsCaseBattery() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: airPodsMax))
        XCTAssertFalse(m.model.hasCase)
        XCTAssertNil(m.caseBattery, "AirPods Max has no case and must not claim a case level")
    }

    func testTwoCellDeviceStillSplitsLeftAndRight() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: ProximityMessageTests.airPodsPro))
        XCTAssertNil(m.single, "a two-cell device must not populate the single-cell field")
        XCTAssertEqual(m.leftBattery, 90)
        XCTAssertEqual(m.rightBattery, 90)
    }

    func testDeviceStateDisplayNeverShowsZeroForMissingData() {
        var d = DeviceState(id: "x", name: "Test")
        XCTAssertEqual(d.displayBattery, "—")
        d.left = 80
        XCTAssertEqual(d.displayBattery, "80% / —")
        d.right = 80
        XCTAssertEqual(d.displayBattery, "80%")
    }

    func testMinimumBatteryDrivesDeathEstimate() {
        var d = DeviceState(id: "x", name: "Test")
        d.left = 70
        d.right = 20
        d.caseBattery = 5
        // The case is irrelevant to when playback stops; the weaker bud decides.
        XCTAssertEqual(d.minimumBattery, 20)
    }
}
