import XCTest
@testable import EarshotKit

/// Fixtures captured from real hardware on 2026-09-13 (see docs/PROTOCOL.md).
/// Ground truth at capture time, from `system_profiler SPBluetoothDataType`:
/// AirPods Pro (3rd generation), model 0x2027, L 90% · R 92% · case 40%.
final class ProximityMessageTests: XCTestCase {

    /// Company id 4C 00 is prepended: CoreBluetooth hands us the full blob.
    static let airPodsPro = "4c00" + "07190127202b998f110009095a5cff4652e7000000761cb2372224"
    static let airPodsProLater = "4c00" + "07190127202b998f110009095a5cff4652e7000000661cbbeacc5d"
    static let shortVariant = "4c00" + "07110629200b28ffff510b000000007df20200"

    func testDecodesModelFromRealCapture() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: Self.airPodsPro))
        XCTAssertEqual(m.model.id, 0x2027)
        XCTAssertEqual(m.model.name, "AirPods Pro (3rd generation)")
    }

    /// The load-bearing assertion: 0x99 must decode to 90%, matching hardware.
    func testDecodesBatteryMatchingHardware() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: Self.airPodsPro))
        XCTAssertEqual(m.leftBattery, 90)
        XCTAssertEqual(m.rightBattery, 90)
    }

    /// 0x0F means "not reported" and must never surface as 0%, or a healthy
    /// case reads as flat to the user.
    func testUnreportedBatteryIsNilNotZero() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: Self.airPodsPro))
        XCTAssertNil(m.caseBattery, "case nibble 0xF must decode to nil")
        XCTAssertNotEqual(m.caseBattery, 0)
    }

    func testBatteryNibbleEncoding() {
        XCTAssertEqual(ProximityMessage.battery(0), 0)
        XCTAssertEqual(ProximityMessage.battery(5), 50)
        XCTAssertEqual(ProximityMessage.battery(10), 100)
        XCTAssertNil(ProximityMessage.battery(11))
        XCTAssertNil(ProximityMessage.battery(0x0F))
    }

    func testShortVariantParsesWithoutOverreading() throws {
        let m = try XCTUnwrap(ProximityMessage.parse(hex: Self.shortVariant))
        XCTAssertEqual(m.model.id, 0x2029)
        XCTAssertNil(m.caseBattery)
    }

    func testTwoCapturesOfSameDeviceAgree() throws {
        let a = try XCTUnwrap(ProximityMessage.parse(hex: Self.airPodsPro))
        let b = try XCTUnwrap(ProximityMessage.parse(hex: Self.airPodsProLater))
        XCTAssertEqual(a.model.id, b.model.id)
        XCTAssertEqual(a.leftBattery, b.leftBattery)
        XCTAssertEqual(a.lidCounter, b.lidCounter)
    }

    // MARK: - Rejection and robustness

    func testRejectsNonAppleCompany() {
        XCTAssertNil(ProximityMessage.parse(hex: "75000719012720000000000000"))
    }

    func testRejectsOtherAppleMessageTypes() {
        // 0x10 is Continuity "nearby info", not proximity pairing.
        XCTAssertNil(ProximityMessage.parse(hex: "4c00" + "10050a081122334455"))
    }

    func testRejectsTruncatedFrames() {
        XCTAssertNil(ProximityMessage.parse(hex: "4c0007"))
        XCTAssertNil(ProximityMessage.parse(hex: "4c000719"))
        // declares 25 bytes but carries 4 -> must not over-read
        XCTAssertNil(ProximityMessage.parse(hex: "4c00" + "0719" + "01272000"))
    }

    func testDoesNotCrashOnArbitraryInput() {
        for len in 0..<40 {
            let bytes = (0..<len).map { UInt8(($0 &* 37) & 0xFF) }
            _ = ProximityMessage.parse(manufacturerData: Data(bytes))
        }
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let len = Int.random(in: 0...60, using: &rng)
            let bytes = (0..<len).map { _ in UInt8.random(in: 0...255, using: &rng) }
            _ = ProximityMessage.parse(manufacturerData: Data([0x4C, 0x00] + bytes))
        }
    }

    func testHexRoundTrip() throws {
        let d = try XCTUnwrap(Data(hexString: "0a1bff00"))
        XCTAssertEqual([UInt8](d), [0x0a, 0x1b, 0xff, 0x00])
        XCTAssertEqual(d.hexString, "0a1bff00")
        XCTAssertNil(Data(hexString: "abc"))
        XCTAssertNil(Data(hexString: "zz"))
    }
}
