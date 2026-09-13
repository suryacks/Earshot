import Foundation
import EarshotKit

/// Gathers a device snapshot for one-shot CLI commands.
///
/// Disconnected devices only report battery over BLE, so the CLI runs a short
/// scan before printing. Without this, `earshot status` would show "—" for
/// every device sitting in its case, which is exactly the case the tool exists
/// to answer.
@MainActor
final class Collector {
    private let registry = DeviceRegistry()
    /// Captured while scanning: reading it after `stop()` always reports idle.
    private var lastScannerState: BLEScanner.State = .idle

    func snapshot(scanFor seconds: TimeInterval, quiet: Bool = false) -> [DeviceState] {
        var latest: [DeviceState] = []
        var sawAdvert = false

        registry.onChange = { devices in
            latest = devices
            if devices.contains(where: \.batteryFromAdvert) { sawAdvert = true }
        }
        // Ignore the .idle that `stop()` emits, or the final teardown would
        // overwrite the state we actually want to report.
        registry.onScannerStateChange = { [weak self] st in
            if st != .idle { self?.lastScannerState = st }
        }
        registry.start(pollInterval: 3600)

        if !quiet && seconds > 0 && Format.useColor {
            FileHandle.standardError.write("Scanning for nearby devices…\n".data(using: .utf8)!)
        }

        // `system_profiler` runs off the main thread and takes 200-500 ms. Even
        // with scanning disabled we have to pump the run loop until it reports,
        // or `--scan 0` returns an empty list rather than the connected devices.
        // Waiting on `hasProfilerData` specifically, not on any update: a BLE
        // advert can arrive first, and returning then would mark every device
        // unpaired because pairing is only known from the profiler.
        let profilerDeadline = Date().addingTimeInterval(5)
        while !registry.hasProfilerData && Date() < profilerDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            if registry.scannerState != .idle { lastScannerState = registry.scannerState }
        }

        // Then keep scanning for the requested window, stopping early once BLE
        // adverts have arrived so the common case feels instant.
        let scanDeadline = Date().addingTimeInterval(seconds)
        let earliestExit = Date().addingTimeInterval(min(1.5, seconds))
        while Date() < scanDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            if registry.scannerState != .idle { lastScannerState = registry.scannerState }
            if sawAdvert && Date() >= earliestExit { break }
        }

        registry.stop()
        return latest
    }

    func scannerState() -> BLEScanner.State { lastScannerState }
}
