import Foundation

/// The merge rules, as a pure function so they can be tested without Bluetooth
/// hardware, a desktop session, or real time passing.
///
/// Three feeds disagree in predictable ways, and the rules below encode which
/// one wins:
///
///   * A *connected* device's levels come from `system_profiler`, which is
///     side-labelled and exact. An advert must never overwrite them - adverts
///     round to 10%, so doing so would make a connected reading jump around.
///   * A *disconnected* device has no other source, so the advert is used.
///   * When several peripherals share a model, the nearest wins, because your
///     own AirPods are closer than the ones across the café.
///   * Adverts older than `ttl` are dropped rather than shown stale.
public enum DeviceMerge {

    public static func merge(
        profiled: [DeviceState],
        adverts: [BLEObservation],
        connectedAddresses: Set<String>,
        now: Date = Date(),
        ttl: TimeInterval = 30
    ) -> [DeviceState] {

        let fresh = adverts.filter { now.timeIntervalSince($0.date) < ttl }

        func nearest(_ productID: UInt16) -> BLEObservation? {
            fresh.filter { $0.message.model.id == productID }.max { $0.rssi < $1.rssi }
        }

        var out: [DeviceState] = []
        var claimed = Set<UInt16>()

        for var d in profiled {
            if let a = d.address {
                d.isConnected = connectedAddresses.contains(BluetoothControl.normalize(a))
            }
            let advert = d.productID.flatMap(nearest)

            if d.isConnected {
                d.lastSeen = now
                d.batteryFromAdvert = false
                // Keep the precise levels, but take the fresher RSSI: the
                // proximity finder needs it to update live.
                if let advert {
                    d.rssi = advert.rssi
                    claimed.insert(advert.message.model.id)
                }
            } else if let advert {
                apply(advert.message, to: &d)
                d.rssi = advert.rssi
                d.lastSeen = advert.date
                d.batteryFromAdvert = true
                claimed.insert(advert.message.model.id)
            }
            out.append(d)
        }

        // Apple headphones broadcasting nearby that this Mac is not paired with.
        // Kept separate so a stranger's AirPods can never appear to be yours.
        let unclaimed = Dictionary(grouping: fresh.filter { !claimed.contains($0.message.model.id) },
                                   by: { $0.message.model.id })
            .compactMapValues { $0.max { $0.rssi < $1.rssi } }

        for obs in unclaimed.values {
            var d = DeviceState(id: "ble-\(obs.peripheralID.uuidString)", name: obs.message.model.name)
            d.productID = obs.message.model.id
            d.kind = .headphones
            d.isPaired = false
            apply(obs.message, to: &d)
            d.rssi = obs.rssi
            d.lastSeen = obs.date
            d.batteryFromAdvert = true
            out.append(d)
        }

        return out.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.isPaired != $1.isPaired { return $0.isPaired }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func apply(_ m: ProximityMessage, to d: inout DeviceState) {
        d.left = m.leftBattery
        d.right = m.rightBattery
        d.caseBattery = m.caseBattery
        d.single = m.single
        d.leftCharging = m.leftCharging
        d.rightCharging = m.rightCharging
        d.caseCharging = m.caseCharging
        d.leftInEar = m.leftInEar
        d.rightInEar = m.rightInEar
    }
}
