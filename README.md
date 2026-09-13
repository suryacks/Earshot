# Earshot

A macOS companion for AirPods and Bluetooth audio devices — battery HUD when you
open the case, device dashboard, audio routing, and a proximity finder for when
you've lost a bud in the couch.

An independent reimplementation in the spirit of
[AirBuddy](https://v3.airbuddy.app), built for personal use. Not affiliated with
it, and not a competitor — see [Legal](#legal).

> **Status: pre-implementation.** Feasibility is proven and the scope is
> written. No app code yet. What's here is the research that de-risks it.

## Why this exists

The premise depends on one thing being true: that macOS still hands Apple's
proximity-pairing BLE broadcast to third-party apps. On several Apple platforms
it does not. So that got tested before anything got built.

It works. On macOS 26.5.2, a 20-second scan captured 26 proximity-pairing
packets, and the decode matched ground truth on both axes:

```
07 19 | 01 27 20 2b 99 8f 11 00 09 | <16 bytes encrypted>
              └──┬──┘  └┬┘
                 │      └─ 0x99 → L 90% · R 90%   (actual: 90% / 92%) ✅
                 └──────── 0x2027 → AirPods Pro    (matches Product ID) ✅
```

Everything else was probed the same way, including the parts that **failed** —
the private `BluetoothManager.framework` rejects unsigned clients, and
MediaRemote is unresolved. Those are written down as plainly as the wins.

## What's verified

| Capability | Status | Path |
|---|---|---|
| Battery while disconnected (lid-open HUD) | ✅ verified | CoreBluetooth `0x004C` / `0x07` |
| Battery while connected (L/R/case) | ✅ verified | `system_profiler` |
| Connect / disconnect | ✅ verified | public `IOBluetooth` |
| Audio output routing | ✅ verified | CoreAudio |
| Audio Input Lock | ✅ verified | CoreAudio |
| Now Playing | ⚠️ unresolved | MediaRemote likely gated; AppleScript fallback proven |
| Magic peripheral battery | ⚠️ untested | no hardware available |
| ANC / Spatial Audio control | ❌ blocked | private L2CAP path |
| iPhone / iPad / Watch battery | ❌ out of scope | encrypted Continuity payloads |

Full evidence, including the negative results: **[docs/FEASIBILITY.md](docs/FEASIBILITY.md)**

## Planned features

Parity with the core of AirBuddy — lid-open HUD, dashboard, battery alerts,
audio routing, Audio Input Lock, widgets, Shortcuts, AppleScript.

Plus five additions that AirBuddy doesn't have, four of which ride on data the
probes already prove we can read:

- **Proximity finder** — live RSSI hot/cold meter to locate a bud that's out of
  the case and not connected. The RSSI is already in every packet.
- **Battery history + drain prediction** — "≈37 min left at this rate" instead
  of a bare percentage.
- **Per-app audio rules** — force input/output per frontmost app.
- **`earshot` CLI with JSON output** — scriptable, tmux/Sketchybar-friendly.
- **Battery-health report** — long-term capacity fade.

Effort estimates, build order and architecture: **[docs/SCOPE.md](docs/SCOPE.md)**

## Repository layout

```
docs/
  FEASIBILITY.md   probe results — what works, what doesn't, with evidence
  SCOPE.md         feature scope, effort, build order, architecture
  PROTOCOL.md      0x07 message layout + captured packet fixtures
research/
  blescan.swift    the BLE scanner that proved the premise
  probes/          CoreAudio, IOBluetooth, BluetoothManager, MediaRemote probes
```

## Running the probes

```sh
cd research
swiftc -O blescan.swift -o blescan && ./blescan        # 20s scan, exits 0 if 0x07 seen
```

Grant Bluetooth permission to the invoking terminal when prompted. The other
probes build the same way (`clang -fobjc-arc -framework Foundation ...` for the
`.m` files — see the header comment in each).

To resolve the one open question, start audio playing and run the MediaRemote
probe — a non-empty dictionary means Now Playing can use the fast path.

## Next step

Milestone 1: BLE scanner → device model → lid-open HUD → connect/disconnect.
~2 weeks, every dependency verified. If the HUD feels good, the project is real.

## Legal

Reimplementing functionality for personal use is fine. This project will not
ship under the AirBuddy name, reuse its assets, or redistribute Apple's product
renders. AirBuddy is a commercial product by Guilherme Rambo and deserves to
stay one — if you want a polished, supported version of this, **buy AirBuddy**.

## License

MIT — see [LICENSE](LICENSE).
