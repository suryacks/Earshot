import Foundation

/// Battery for iPhone, iPad and Apple Watch, via a companion Shortcut.
///
/// Apple's Continuity "nearby info" broadcasts carry this over the air, but they
/// are encrypted with keys synced through the iCloud keychain, and the Find My
/// cache is encrypted too (verified: binary plist wrapping `encryptedData`,
/// entropy 7.99/8.0). Neither is reachable by a third-party app.
///
/// So rather than reverse-engineer something fragile, the device reports its own
/// battery. An iOS Shortcut automation writes a small JSON file into iCloud
/// Drive; this reads it. Fully supported APIs on both ends, survives OS updates,
/// and works anywhere rather than only in Bluetooth range - the trade is that it
/// needs a one-time setup and is as fresh as the automation's schedule.
///
/// Expected file, one per device, in `iCloud Drive/Earshot/`:
/// ```json
/// { "name": "Surya's iPhone", "kind": "phone",
///   "battery": 72, "charging": false,
///   "updated": "2026-09-13T16:40:00Z" }
/// ```
public final class MobileDeviceStore: @unchecked Sendable {

    public struct Report: Codable, Sendable, Equatable {
        public var name: String
        public var kind: String?
        public var battery: Int
        public var charging: Bool?
        public var updated: Date?
    }

    /// Reports older than this are dropped: a day-old battery reading is a lie
    /// dressed as data.
    public var maxAge: TimeInterval = 6 * 3600

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    public var onChange: (() -> Void)?

    public static var defaultDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Earshot",
                                    isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    public var directoryPath: String { directory.path }
    public var directoryExists: Bool {
        FileManager.default.fileExists(atPath: directory.path)
    }

    /// Creates the drop folder so the user has somewhere to point the Shortcut.
    @discardableResult
    public func createDirectory() -> Bool {
        (try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)) != nil
    }

    /// Watches for changes. iCloud can materialise files without a local write
    /// event, so callers should also poll on a timer.
    public func startWatching() {
        guard source == nil, directoryExists else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib], queue: .main)
        s.setEventHandler { [weak self] in self?.onChange?() }
        s.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
            self?.watchedFD = -1
        }
        s.resume()
        source = s
    }

    public func stopWatching() {
        source?.cancel()
        source = nil
    }

    deinit { source?.cancel() }

    public func read(now: Date = Date()) -> [DeviceState] {
        guard directoryExists else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            // Shortcuts' date formatting is not guaranteed ISO-8601, so several
            // shapes are accepted rather than silently dropping the report.
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = format
                if let date = f.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(),
                                                   debugDescription: "unrecognised date \(raw)")
        }

        var out: [DeviceState] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let report = try? decoder.decode(Report.self, from: data)
            else { continue }

            // Fall back to the file's own mtime when the Shortcut omitted a date.
            let stamp = report.updated
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            guard now.timeIntervalSince(stamp) <= maxAge else { continue }
            guard (0...100).contains(report.battery) else { continue }

            var d = DeviceState(id: "mobile-\(file.deletingPathExtension().lastPathComponent)",
                                name: report.name)
            d.kind = Self.kind(from: report.kind ?? "", name: report.name)
            d.single = report.battery
            d.leftCharging = report.charging ?? false
            d.isPaired = true
            d.isConnected = false
            d.lastSeen = stamp
            d.isCompanionReport = true
            out.append(d)
        }
        return out.sorted { $0.name < $1.name }
    }

    static func kind(from raw: String, name: String) -> DeviceState.Kind {
        let hay = (raw + " " + name).lowercased()
        if hay.contains("watch") { return .watch }
        if hay.contains("pad") { return .tablet }
        if hay.contains("phone") { return .phone }
        return .phone
    }
}
