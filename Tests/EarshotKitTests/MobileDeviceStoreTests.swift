import XCTest
@testable import EarshotKit

final class MobileDeviceStoreTests: XCTestCase {
    private var dir: URL!
    private var store: MobileDeviceStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earshot-mobile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = MobileDeviceStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ json: String) {
        try? json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func stamp(_ offset: TimeInterval = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    func testReadsAReport() throws {
        write("iphone.json", """
        {"name":"My iPhone","kind":"phone","battery":72,"charging":false,"updated":"\(stamp())"}
        """)
        let devices = store.read()
        XCTAssertEqual(devices.count, 1)
        let d = try XCTUnwrap(devices.first)
        XCTAssertEqual(d.name, "My iPhone")
        XCTAssertEqual(d.single, 72)
        XCTAssertEqual(d.kind, .phone)
        XCTAssertTrue(d.isCompanionReport)
    }

    func testInfersKindFromNameWhenMissing() {
        write("a.json", #"{"name":"Surya's Apple Watch","battery":50,"updated":"\#(stamp())"}"#)
        write("b.json", #"{"name":"Work iPad","battery":50,"updated":"\#(stamp())"}"#)
        let kinds = Set(store.read().map(\.kind))
        XCTAssertTrue(kinds.contains(.watch))
        XCTAssertTrue(kinds.contains(.tablet))
    }

    /// A day-old battery reading is a lie dressed as data.
    func testStaleReportsAreDropped() {
        write("old.json", """
        {"name":"Old iPhone","battery":72,"updated":"\(stamp(-48 * 3600))"}
        """)
        XCTAssertTrue(store.read().isEmpty)
    }

    func testFreshnessWindowIsConfigurable() {
        write("x.json", #"{"name":"iPhone","battery":50,"updated":"\#(stamp(-3600))"}"#)
        store.maxAge = 600
        XCTAssertTrue(store.read().isEmpty)
        store.maxAge = 7200
        XCTAssertEqual(store.read().count, 1)
    }

    func testImpossibleBatteryValuesAreRejected() {
        write("a.json", #"{"name":"A","battery":150,"updated":"\#(stamp())"}"#)
        write("b.json", #"{"name":"B","battery":-5,"updated":"\#(stamp())"}"#)
        XCTAssertTrue(store.read().isEmpty)
    }

    /// Shortcuts' date output is not guaranteed ISO-8601.
    func testAcceptsAlternativeDateFormats() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        write("x.json", #"{"name":"iPhone","battery":60,"updated":"\#(f.string(from: Date()))"}"#)
        XCTAssertEqual(store.read().count, 1)
    }

    /// If the Shortcut omits a timestamp entirely, the file's own mtime stands
    /// in, so a working setup is not silently ignored.
    func testFallsBackToFileModificationDate() {
        write("x.json", #"{"name":"iPhone","battery":60}"#)
        XCTAssertEqual(store.read().count, 1)
    }

    func testMalformedFilesAreSkippedNotFatal() {
        write("bad.json", "{ this is not json")
        write("good.json", #"{"name":"iPhone","battery":60,"updated":"\#(stamp())"}"#)
        write("ignored.txt", #"{"name":"Nope","battery":10}"#)
        let devices = store.read()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.name, "iPhone")
    }

    func testMissingDirectoryIsNotAnError() {
        let missing = MobileDeviceStore(directory: dir.appendingPathComponent("nope"))
        XCTAssertFalse(missing.directoryExists)
        XCTAssertTrue(missing.read().isEmpty)
    }

    func testChargingFlagIsCarried() throws {
        write("x.json", #"{"name":"iPhone","battery":60,"charging":true,"updated":"\#(stamp())"}"#)
        XCTAssertTrue(try XCTUnwrap(store.read().first).isCharging)
    }
}
