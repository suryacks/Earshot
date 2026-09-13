import XCTest
@testable import EarshotKit

final class BatteryStoreTests: XCTestCase {
    private var url: URL!
    private var store: BatteryStore!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("earshot-test-\(UUID().uuidString).sqlite")
        store = try XCTUnwrap(BatteryStore(url: url))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func device(_ left: Int?, _ right: Int? = nil, charging: Bool = false) -> DeviceState {
        var d = DeviceState(id: "dev", name: "Test AirPods")
        d.left = left
        d.right = right ?? left
        d.leftCharging = charging
        d.isConnected = true
        return d
    }

    /// `record` is asynchronous; flush by issuing a synchronous read.
    private func flush() { _ = store.history(deviceID: "dev", since: .distantPast) }

    func testRecordsAndReadsBack() {
        store.record([device(80)])
        flush()
        let samples = store.history(deviceID: "dev", since: .distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.level, 80)
    }

    /// A device idling at one level for an hour should cost one row, not 180.
    func testUnchangedReadingsAreDeduplicated() {
        for _ in 0..<20 { store.record([device(80)]) }
        flush()
        XCTAssertEqual(store.history(deviceID: "dev", since: .distantPast).count, 1)
    }

    func testChangedReadingIsRecorded() {
        store.record([device(80)])
        store.record([device(70)])
        flush()
        XCTAssertEqual(store.history(deviceID: "dev", since: .distantPast).count, 2)
    }

    func testDevicesWithNoBatteryAreNotRecorded() {
        store.record([device(nil)])
        flush()
        XCTAssertTrue(store.history(deviceID: "dev", since: .distantPast).isEmpty)
    }

    func testHistoryTracksTheWeakestCell() {
        var d = DeviceState(id: "dev", name: "Test")
        d.left = 70
        d.right = 30
        store.record([d])
        flush()
        // The weaker bud is what stops playback, so it is what gets stored.
        XCTAssertEqual(store.history(deviceID: "dev", since: .distantPast).first?.level, 30)
    }

    func testHistoryRespectsTimeWindow() {
        store.record([device(80)])
        flush()
        let future = Date().addingTimeInterval(3600)
        XCTAssertTrue(store.history(deviceID: "dev", since: future).isEmpty)
    }

    // MARK: - Drain prediction

    func testNoPredictionWithoutEnoughData() {
        store.record([device(80)])
        flush()
        XCTAssertNil(store.timeToEmpty(deviceID: "dev"))
    }

    func testNoPredictionWhileCharging() {
        for level in [50, 60, 70, 80, 90] {
            store.record([device(level, charging: true)])
        }
        flush()
        XCTAssertNil(store.timeToEmpty(deviceID: "dev"),
                     "a charging device is not heading toward empty")
    }

    func testNoPredictionWhenLevelIsFlat() {
        // Four identical readings are a flat line; extrapolating gives infinity.
        for _ in 0..<4 { store.record([device(80)]) }
        flush()
        XCTAssertNil(store.timeToEmpty(deviceID: "dev"))
    }

    /// The regression is fitted over real timestamps, so this drives the SQL
    /// layer directly to control them.
    func testPredictsTimeToEmptyFromADischargeCurve() throws {
        let now = Date()
        // 100% -> 60% over two hours = 20%/hour, so 60% should last ~3 hours.
        let points: [(TimeInterval, Int)] = [
            (-7200, 100), (-5400, 90), (-3600, 80), (-1800, 70), (0, 60),
        ]
        for (offset, level) in points {
            insertRaw(level: level, at: now.addingTimeInterval(offset))
        }
        let eta = try XCTUnwrap(store.timeToEmpty(deviceID: "dev", now: now))
        let hours = eta / 3600
        XCTAssertEqual(hours, 3.0, accuracy: 0.35, "expected roughly three hours, got \(hours)")
    }

    func testPredictionIgnoresRisingLevels() {
        let now = Date()
        for (i, level) in [40, 50, 60, 70, 80].enumerated() {
            insertRaw(level: level, at: now.addingTimeInterval(Double(i - 4) * 1800))
        }
        XCTAssertNil(store.timeToEmpty(deviceID: "dev", now: now),
                     "a rising level must not produce a time-to-empty")
    }

    func testPruneRemovesOldRows() {
        insertRaw(level: 50, at: Date().addingTimeInterval(-200 * 86_400))
        insertRaw(level: 60, at: Date())
        XCTAssertEqual(store.history(deviceID: "dev", since: .distantPast).count, 2)
        store.prune(olderThan: 120)
        flush()
        XCTAssertEqual(store.history(deviceID: "dev", since: .distantPast).count, 1)
    }

    /// Writes a row with an explicit timestamp, which `record` cannot do.
    private func insertRaw(level: Int, at date: Date) {
        var d = DeviceState(id: "dev", name: "Test")
        d.left = level
        d.right = level
        store.recordForTesting(d, at: date)
        flush()
    }
}

/// Privacy: devices that aren't paired with this Mac must never reach disk.
final class BatteryStorePrivacyTests: XCTestCase {
    private var url: URL!
    private var store: BatteryStore!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("earshot-privacy-\(UUID().uuidString).sqlite")
        store = try XCTUnwrap(BatteryStore(url: url))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: url)
    }

    func testPurgeRemovesUnpairedRowsButKeepsOwnDevices() {
        var stranger = DeviceState(id: "ble-\(UUID().uuidString)", name: "Someone's AirPods")
        stranger.left = 50
        stranger.right = 50
        var mine = DeviceState(id: "aa:bb:cc:dd:ee:ff", name: "My AirPods")
        mine.left = 80
        mine.right = 80

        store.record([stranger, mine])
        _ = store.history(deviceID: mine.id, since: .distantPast)   // flush
        XCTAssertEqual(store.history(deviceID: stranger.id, since: .distantPast).count, 1)

        store.purgeUnpairedDevices()
        _ = store.history(deviceID: mine.id, since: .distantPast)   // flush

        XCTAssertTrue(store.history(deviceID: stranger.id, since: .distantPast).isEmpty,
                      "a stranger's device must not remain on disk")
        XCTAssertEqual(store.history(deviceID: mine.id, since: .distantPast).count, 1,
                       "the user's own device must survive the purge")
    }
}
