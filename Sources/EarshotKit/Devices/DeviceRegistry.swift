import Foundation

/// Single source of truth. Merges three feeds into one device list:
///
///   * `system_profiler` - authoritative for *connected* devices, explicit L/R
///   * BLE adverts       - the only battery source for *disconnected* devices
///   * IOBluetooth       - pairing and live connection state
///
/// Everything downstream (menu bar, HUD, widgets, CLI) subscribes here, so the
/// three feeds can never disagree on screen.
@MainActor
public final class DeviceRegistry {

    public private(set) var devices: [DeviceState] = [] { didSet { onChange?(devices) } }
    public var onChange: (([DeviceState]) -> Void)?
    /// Fires when a lid opens and we could attribute it to a known device.
    public var onLidOpened: ((DeviceState) -> Void)?

    private let scanner = BLEScanner()
    private var profiled: [DeviceState] = []
    /// True once a `system_profiler` snapshot has landed. Callers that need the
    /// paired-device list (rather than just BLE adverts) must wait for this:
    /// without it every device looks unpaired, because pairing is only known
    /// from the profiler.
    public private(set) var hasProfilerData = false
    /// Latest advert per peripheral. Adverts carry no stable address, so the
    /// model is the only join key back to a paired device - but several
    /// peripherals can share a model, so they are stored separately and the
    /// nearest one wins at merge time.
    private var adverts: [UUID: BLEObservation] = [:]
    private var pollTimer: Timer?
    private var store: BatteryStore?
    private let mobile = MobileDeviceStore()
    private var mobileDevices: [DeviceState] = []

    /// Adverts older than this are stale - the device left or went quiet.
    private let advertTTL: TimeInterval = 30
    public var scannerState: BLEScanner.State { scanner.state }
    public var onScannerStateChange: ((BLEScanner.State) -> Void)?

    public init(store: BatteryStore? = nil) {
        self.store = store
    }

    public func start(pollInterval: TimeInterval = 20) {
        scanner.onObservation = { [weak self] obs in self?.ingest(obs) }
        scanner.onStateChange = { [weak self] st in self?.onScannerStateChange?(st) }
        scanner.onLidOpened = { [weak self] obs in
            guard let self else { return }
            self.ingest(obs)
            if let d = self.devices.first(where: { $0.productID == obs.message.model.id && $0.isPaired }) {
                self.onLidOpened?(d)
            }
        }
        scanner.start()
        refreshProfiled()

        // iCloud can materialise a file without a local write event, so the
        // watcher is backed up by the same poll timer as system_profiler.
        mobile.onChange = { [weak self] in self?.refreshMobile() }
        mobile.startWatching()
        refreshMobile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProfiled()
                self?.refreshMobile()
            }
        }
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        mobile.stopWatching()
        scanner.stop()
    }

    /// Companion reports from iPhone/iPad/Watch. Cheap (a few small files), so
    /// it runs on the main thread.
    public func refreshMobile() {
        let fresh = mobile.read()
        guard fresh != mobileDevices else { return }
        mobileDevices = fresh
        rebuild()
    }

    public var companionDirectory: String { mobile.directoryPath }
    public var companionConfigured: Bool { mobile.directoryExists }
    @discardableResult
    public func createCompanionDirectory() -> Bool { mobile.createDirectory() }

    // MARK: - Feeds

    private func ingest(_ obs: BLEObservation) {
        adverts[obs.peripheralID] = obs
        rebuild()
    }

    /// Strongest recent advert for a model. Your own AirPods are the nearest
    /// ones; a neighbour's identical pair is further away and must not be
    /// allowed to overwrite your battery reading.
    private func bestAdvert(for productID: UInt16, now: Date) -> BLEObservation? {
        adverts.values
            .filter { $0.message.model.id == productID && now.timeIntervalSince($0.date) < advertTTL }
            .max { $0.rssi < $1.rssi }
    }

    /// `system_profiler` is slow, so it runs off the main thread and hops back.
    public func refreshProfiled() {
        Task.detached(priority: .utility) {
            let snap = SystemProfiler.snapshot()
            await MainActor.run {
                self.profiled = snap
                self.hasProfilerData = true
                self.rebuild()
            }
        }
    }

    // MARK: - Merge

    private func rebuild() {
        let connected = Set(
            BluetoothControl.pairedDevices().filter(\.isConnected).map(\.address)
        )
        let merged = DeviceMerge.merge(
            profiled: profiled,
            adverts: Array(adverts.values),
            connectedAddresses: connected,
            now: Date(),
            ttl: advertTTL
        )
        // Companion reports describe devices this Mac cannot see over Bluetooth,
        // so they are appended rather than merged - there is nothing to merge
        // them against.
        let all = merged + mobileDevices
        devices = all
        // Only the user's own devices are persisted. Writing a stranger's
        // AirPods to disk because they walked past is a privacy problem, and
        // it fills the history with devices nobody can act on.
        store?.record(all.filter(\.isPaired))
    }

    // MARK: - Queries

    public var connected: [DeviceState] { devices.filter(\.isConnected) }
    public var primary: DeviceState? {
        connected.first { $0.kind == .headphones } ?? connected.first
    }
    public func device(matching query: String) -> DeviceState? {
        let q = query.lowercased()
        return devices.first { $0.name.lowercased() == q }
            ?? devices.first { $0.name.lowercased().contains(q) }
            ?? devices.first { ($0.address ?? "").lowercased() == q }
    }
}
