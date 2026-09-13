# Feasibility Probes

Every claim here was produced by running code on the target machine, not from
documentation. Probe sources live in [`../research/probes`](../research/probes).

**Test bed:** MacBook Pro (BCM_4388C2), macOS 26.5.2 (25F84), Xcode 26.4.1,
Swift 6.3.1. Probe date: 2026-09-13. Test device: AirPods Pro (model `0x2027`).

---

> **Status:** every green item below is now shipping in Earshot, and the two
> open questions have been answered — see §5 (Now Playing, resolved) and §8
> (private framework, confirmed blocked).

## GREEN — verified working

### 1. AirPods battery while disconnected (BLE proximity pairing)

The load-bearing question for the whole project. Apple filters its own
manufacturer data out of scan results on some platforms; on macOS 26.5.2 it
does **not**.

20-second scan: 647 advertisement packets, 555 Apple (`0x004C`), **26 of type
`0x07`** (proximity pairing).

```
07 19 | 01 27 20 2b 99 8f 11 00 09 | 09 5a 5c ff 46 52 e7 00 ... (16 bytes)
 |  |    |   \___/  |  |  |  |  |  |  \_______ encrypted region
 |  |    |     |    |  |  |  |  |  └─ connection state
 |  |    |     |    |  |  |  └─ device color
 |  |    |     |    |  |  └─ lid-open counter
 |  |    |     |    |  └─ case battery nibble + charging flags
 |  |    |     |    └─ pod battery: 0x99 → L=90% R=90%   (actual 90%/92%) ✅
 |  |    |     └─ status flags (in-ear, primary bud, lid)
 |  |    |        model 0x2027 little-endian → AirPods Pro ✅ matches Product ID
 |  |    └─ prefix / paired status
 |  └─ payload length (0x19 = 25)
 └─ message type 0x07
```

Both the model ID and the battery nibbles independently match ground truth from
`system_profiler`. The first 9 payload bytes are plaintext and carry everything
the lid-open HUD needs; the trailing 16 bytes are encrypted and are not needed.

A shorter 17-byte `0x07` variant from a second nearby device (model `0x2029`)
was also captured — the parser must branch on payload length.

> **Unverified lead:** bytes `46 52 e7` inside the nominally-encrypted region
> match the tail of this Mac's own Bluetooth controller address
> (`84:2F:57:46:52:E7`). If that is the paired-host identifier rather than
> ciphertext, it is a clean way to tell *my* AirPods from a stranger's on a
> crowded train. Needs confirmation against a second Mac before relying on it.

### 2. Battery for connected devices (L / R / case)

`system_profiler SPBluetoothDataType` reports `Case Battery Level: 40%`,
`Left: 90%`, `Right: 92%`, plus firmware, serials and RSSI.

IORegistry does **not** carry these for Bluetooth audio devices — only for
USB/Lightning HID. `ioreg` is a dead end here; don't waste time on it.

Cost is ~200–500 ms per invocation, so poll it on a slow timer (or on BLE
state-change events) rather than in a tight loop.

### 3. Connect / disconnect

Public `IOBluetooth`. `IOBluetoothDevice.pairedDevices()` enumerated all 10
paired devices with correct `isConnected` state; `openConnection` /
`closeConnection` both respond. No private API required.

### 4. Audio routing and Audio Input Lock

Public CoreAudio. Probe confirms:

```
default OUTPUT device settable: true   → audio routing
default INPUT  device settable: true   → Audio Input Lock
```

Input Lock is then just an `AudioObjectAddPropertyListener` on the default-input
property that writes the preferred device back whenever something else changes
it. Entirely supported API.

---

## YELLOW — works with caveats, or unresolved

### 5. Now Playing — **RESOLVED: MediaRemote is gated**

`MediaRemote.framework` loads and all four symbols resolve
(`MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteSendCommand`,
`MRMediaRemoteGetNowPlayingApplicationIsPlaying`,
`MRNowPlayingClientGetBundleIdentifier`).

The first probe was inconclusive because Spotify happened to be *paused*. Re-run
later with audio **actually playing**, `MRMediaRemoteGetNowPlayingInfo` still
returned an empty dictionary. That settles it: Apple's macOS 15.4 restriction is
still in force on 26.5, and unentitled callers get nothing.

**The AppleScript fallback is confirmed working** and is what ships. It returns
full metadata even while paused:

```
Chella Magale — Anirudh Ravichander   (album: Jana Nayagan)
```

Two implementation notes paid for in debugging time:

* The callback **must** be declared `@escaping`. MediaRemote answers
  asynchronously and retains the block; a non-escaping declaration makes Swift
  free it on return and the later callback lands on freed memory. This crashed
  reproducibly.
* AppleScript variable names must dodge reserved tokens. `st` is a date-ordinal
  abbreviation and fails to parse with a misleading "Expected expression"
  error.

Coverage: Music and Spotify, via `NowPlayingSource`. Browser-hosted media is not
reachable without the entitlement.

### 6. Magic Handoff

Depends on the blocked private path in §8, or on a connect-to-already-paired
dance via public `IOBluetooth`. The public route likely works but will be
slower and less seamless than AirBuddy's. Prototype before committing.

### 7. Magic Mouse / Keyboard / Trackpad battery — still untested

**Untested — no such hardware paired to this machine.** The standard route
(`ioreg -c AppleDeviceManagementHIDEventService` → `BatteryPercent`) returned
only the internal keyboard here. `system_profiler` also reports battery for
these peripherals, so at least one path should work. Confirm when hardware is
available.

---

## RED — blocked or expensive

### 8. `BluetoothManager.framework` (private)

Loads; `BluetoothManager` and `BluetoothDevice` classes resolve;
`sharedInstance` returns an object. But after a 3-second runloop spin:

```
available=0  powered=0  connectedDevices: 0
```

Bluetooth was demonstrably on. `bluetoothd` rejects the client. Ad-hoc signing
did not change the result — it likely wants a real Developer ID signature and
possibly an Apple-private entitlement that is not grantable to third parties.

**Not a blocker:** §2 and §3 cover the same ground through supported APIs. The
cost is polling instead of push notifications.

### 9. ANC / Transparency / Spatial Audio control

These ride on AACP over a private L2CAP channel, reachable in practice through
the framework in §8. Treat as **out of scope** for v1. Reading the current mode
may be possible from the `0x07` status flags; *setting* it is the hard part.

### 10. iPhone / iPad / Apple Watch battery

The hardest item. AirBuddy 3 advertises this "without requiring separate
pairing," but Continuity "nearby info" payloads from non-audio Apple devices are
encrypted with keys synced through the iCloud keychain. The convenient plaintext
prefix that makes AirPods easy has no equivalent here.

Realistic options, in order of preference:
1. **Drop it for v1.** Focus on audio devices, where we have a verified edge.
2. Companion iOS app or Shortcut pushing battery over the LAN — honest, robust,
   user-visible pairing step.
3. Reverse-engineer the Continuity crypto — high effort, fragile across OS
   updates, likely to break.
