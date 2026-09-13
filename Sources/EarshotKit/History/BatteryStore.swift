import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Battery history on disk, and the drain-rate estimate derived from it.
///
/// Readings are deduplicated: a row is written only when a level actually
/// changes, so a device idling at 90% for an hour costs one row, not 180.
public final class BatteryStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.earshot.batterystore")
    private var lastWritten: [String: DeviceState] = [:]

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.sqlite")
    }

    public init?(url: URL? = nil) {
        let path = (url ?? Self.defaultURL).path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            return nil
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("""
            CREATE TABLE IF NOT EXISTS readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                device_name TEXT,
                ts REAL NOT NULL,
                lvl_left INTEGER, lvl_right INTEGER,
                lvl_case INTEGER, lvl_single INTEGER,
                charging INTEGER NOT NULL DEFAULT 0,
                connected INTEGER NOT NULL DEFAULT 0
            );
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_readings_dev_ts ON readings(device_id, ts);")
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// Skips devices with no battery data and unchanged levels.
    public func record(_ devices: [DeviceState]) {
        queue.async { [weak self] in
            guard let self else { return }
            for d in devices {
                guard d.left != nil || d.right != nil || d.single != nil || d.caseBattery != nil else { continue }
                if let prev = self.lastWritten[d.id],
                   prev.left == d.left, prev.right == d.right,
                   prev.caseBattery == d.caseBattery, prev.single == d.single,
                   prev.isCharging == d.isCharging, prev.isConnected == d.isConnected {
                    continue
                }
                self.lastWritten[d.id] = d
                self.insert(d)
            }
        }
    }

    /// Writes one row at an explicit timestamp, bypassing deduplication.
    /// Exists so tests can build a discharge curve without waiting hours.
    public func recordForTesting(_ d: DeviceState, at date: Date) {
        queue.sync { self.insert(d, at: date) }
    }

    private func insert(_ d: DeviceState, at date: Date = Date()) {
        guard let db else { return }
        let sql = """
            INSERT INTO readings
            (device_id, device_name, ts, lvl_left, lvl_right, lvl_case, lvl_single, charging, connected)
            VALUES (?,?,?,?,?,?,?,?,?);
            """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, d.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 2, d.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(st, 3, date.timeIntervalSince1970)
        bindOptional(st, 4, d.left)
        bindOptional(st, 5, d.right)
        bindOptional(st, 6, d.caseBattery)
        bindOptional(st, 7, d.single)
        sqlite3_bind_int(st, 8, d.isCharging ? 1 : 0)
        sqlite3_bind_int(st, 9, d.isConnected ? 1 : 0)
        sqlite3_step(st)
    }

    private func bindOptional(_ st: OpaquePointer?, _ idx: Int32, _ v: Int?) {
        if let v { sqlite3_bind_int(st, idx, Int32(v)) } else { sqlite3_bind_null(st, idx) }
    }

    public struct Sample: Sendable, Equatable {
        public let date: Date
        public let level: Int
        public let charging: Bool
    }

    /// Minimum-cell history, which is what actually predicts death.
    public func history(deviceID: String, since: Date) -> [Sample] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
                SELECT ts, lvl_left, lvl_right, lvl_single, charging FROM readings
                WHERE device_id = ? AND ts >= ? ORDER BY ts ASC;
                """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_text(st, 1, deviceID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(st, 2, since.timeIntervalSince1970)

            var out: [Sample] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let ts = sqlite3_column_double(st, 0)
                var levels: [Int] = []
                for col in Int32(1)...Int32(3) where sqlite3_column_type(st, col) != SQLITE_NULL {
                    levels.append(Int(sqlite3_column_int(st, col)))
                }
                guard let level = levels.min() else { continue }
                out.append(Sample(date: Date(timeIntervalSince1970: ts),
                                  level: level,
                                  charging: sqlite3_column_int(st, 4) == 1))
            }
            return out
        }
    }

    /// Estimated seconds until the minimum cell hits zero, from a least-squares
    /// fit over recent *discharging* samples. `nil` when charging, when there is
    /// too little data, or when the trend is flat or rising - guessing from
    /// noise would be worse than saying nothing.
    public func timeToEmpty(deviceID: String, now: Date = Date()) -> TimeInterval? {
        let samples = history(deviceID: deviceID, since: now.addingTimeInterval(-6 * 3600))
            .filter { !$0.charging }
        guard samples.count >= 4, let last = samples.last else { return nil }
        let span = last.date.timeIntervalSince(samples[0].date)
        guard span >= 600 else { return nil }

        let t0 = samples[0].date.timeIntervalSince1970
        let xs = samples.map { $0.date.timeIntervalSince1970 - t0 }
        let ys = samples.map { Double($0.level) }
        let n = Double(samples.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<samples.count {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        guard den > 0 else { return nil }
        let slope = num / den                       // percent per second
        guard slope < -1e-7 else { return nil }     // flat or charging up
        let seconds = Double(last.level) / -slope
        guard seconds.isFinite, seconds > 0, seconds < 86_400 * 2 else { return nil }
        return seconds
    }

    /// Removes rows for devices that were never paired with this Mac.
    ///
    /// Earlier builds recorded any nearby broadcaster, including ones whose
    /// payload layout was not actually understood, so existing databases carry
    /// rows for strangers' devices and for garbage model ids. Those are deleted
    /// on startup rather than left sitting on disk.
    public func purgeUnpairedDevices() {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            sqlite3_exec(db, "DELETE FROM readings WHERE device_id LIKE 'ble-%';", nil, nil, nil)
            self.lastWritten = self.lastWritten.filter { !$0.key.hasPrefix("ble-") }
        }
    }

    public func prune(olderThan days: Int = 120) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM readings WHERE ts < ?;", -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, cutoff)
            sqlite3_step(st)
        }
    }
}
