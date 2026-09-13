# Earshot

**See your AirPods' battery the moment you open the case — in an interactive
island that grows out of your MacBook's notch.**

A menu bar app for macOS that reads the battery your AirPods broadcast over
Bluetooth LE, shows it in a notch island you can hover and click, keeps a
history so it can tell you how long they'll actually last, and stops macOS
hijacking your microphone every time a headset connects.

Free, open source, no telemetry, no account. Built in the spirit of
[AirBuddy](https://v3.airbuddy.app) — which is excellent, and which you should
buy if you want a polished, supported product. This is the version I wanted to
build for myself.

```
● FruitPods Pro3    L  85%  R  86%  case  40%   -52 dBm
○ AirPods Max       ██████████ 100%             via BLE
```

---

## Why it exists

macOS knows your AirPods' battery, but only shows it once they're already
connected, buried in a Control Center submenu. The interesting moment — *I just
opened the case, can I get through this call?* — is exactly when it tells you
nothing.

AirPods actually broadcast their battery continuously over Bluetooth LE, whether
they're connected or not. Earshot listens for that broadcast.

## Features

**The island**
- An interactive island in the MacBook notch — hover to expand, click to act
- Slides out briefly when you open the case, connect, or disconnect, then
  retracts. Spring-animated, and it stays quiet while a Focus is on
- Device batteries, connect/disconnect buttons, and Now Playing with album
  artwork and transport controls, all inside it
- Notch geometry is measured from the display, so it fits the 14", 16" and Air
  correctly. Macs without a notch get a floating island below the menu bar

**Battery**
- Heads-up display when you open the case, before the AirPods connect
- Left, right and case levels, with charging state
- Menu bar percentage that tracks whichever device matters right now
- Low-battery alerts that fire **once** per discharge, not every 20 seconds
- Battery history in SQLite, with a real drain-rate estimate:
  *"≈37m remaining at the current rate"* instead of a bare percentage

**Finding things**
- **Proximity finder** — a live hot/cold meter driven by signal strength, for
  locating a bud that's out of the case and not connected. AirBuddy has no
  equivalent, and it's the feature I use most.

**Your devices, not everyone's**
- Strangers' AirPods broadcast battery to the whole room. Earshot **hides
  devices that aren't paired with this Mac** by default — you can opt in when
  you actually want to find something to connect to.
- **iPhone, iPad and Apple Watch battery** via a companion Shortcut. Apple
  encrypts what those devices broadcast, so they report it themselves into
  iCloud Drive. Two-minute setup: [docs/CROSS-DEVICE.md](docs/CROSS-DEVICE.md)

**Audio**
- One-click output switching from the menu bar
- **Audio Input Lock** — pins your microphone so macOS can't silently switch it
  to a headset mic mid-call, quietly wrecking your audio quality
- **Per-app audio rules** — force a specific input/output when a given app comes
  to the front

**Everything else**
- Connect and disconnect any paired Bluetooth device
- Now Playing, with artist and track
- A real CLI (`earshot status --json`) for scripting, tmux, Sketchybar
- `earshot://` URL scheme so Shortcuts can drive it
- Global hotkey (⌥⌘E) for the dashboard
- Launch at login

## Install

Earshot isn't notarized — I don't pay for a Developer ID — so you build it
yourself. It takes about a minute and needs only Xcode's command line tools.

```sh
git clone https://github.com/suryacks/Earshot.git
cd Earshot
./Scripts/build-app.sh
./Scripts/install.sh
```

That installs `Earshot.app` to `/Applications`, puts the `earshot` CLI in
`/usr/local/bin`, and launches the app. Look for the AirPods icon in your menu
bar.

**Requirements:** macOS 14 or later, Xcode 15+ command line tools
(`xcode-select --install`). Tested on macOS 26.5 with Apple silicon.

### Permissions

macOS will ask for these. Earshot degrades gracefully without them, but:

| Permission | Why | Without it |
|---|---|---|
| **Bluetooth** | Reading the BLE battery broadcast | Disconnected devices show no battery — the main feature stops working |
| **Notifications** | Low-battery alerts | No alerts |
| **Automation** (Music/Spotify) | Now Playing | Now Playing stays empty |

If you miss the Bluetooth prompt, enable it under **System Settings → Privacy &
Security → Bluetooth** and relaunch.

### Uninstall

```sh
rm -rf /Applications/Earshot.app /usr/local/bin/earshot
rm -rf ~/Library/Application\ Support/Earshot
defaults delete app.earshot.Earshot
```

## The CLI

```sh
earshot status              # battery for your devices
earshot status --all        # include nearby devices you don't own
earshot status --json       # machine-readable
earshot find "AirPods Pro"  # live proximity meter
earshot watch --raw         # stream BLE adverts, with payload hex
earshot connect "AirPods"   # connect / disconnect / toggle
earshot output "Speakers"   # switch audio output
earshot history "AirPods"   # battery curve + time-to-empty
earshot nowplaying --json
```

`status` runs a short BLE scan first, because devices sitting in a case only
report battery over the air. `--scan 0` skips it when you only care about
what's connected.

## Shortcuts and automation

Shortcuts drives Earshot through its URL scheme — use the **Open URL** action:

```
earshot://dashboard
earshot://preview                 # replay the lid-open card
earshot://connect?name=AirPods
earshot://toggle?name=AirPods
earshot://output?name=MacBook%20Pro%20Speakers
earshot://inputlock?on=1
```

Anything more involved is a one-liner against the CLI.

## What doesn't work, and why

I'd rather tell you up front than have you find out.

| | Status |
|---|---|
| **iPhone / iPad / Watch battery** | **Supported, with setup.** The over-the-air path is closed: Continuity payloads are encrypted, and the Find My cache measures 7.99/8.0 bits of entropy — solid ciphertext. So the device reports its own battery through a Shortcut that writes to iCloud Drive. Readings are as fresh as the automation, not live. [Setup →](docs/CROSS-DEVICE.md) |
| **ANC / Transparency / Spatial Audio switching** | **Not supported.** Riding on a private L2CAP channel reachable only through `BluetoothManager.framework`, which refuses unsigned clients. Reading the current mode may be possible; setting it isn't. |
| **Desktop widgets** | **Not implemented.** WidgetKit needs an app-extension target, which Swift Package Manager can't produce. The notch island covers most of what I wanted widgets for. Converting to an Xcode project would unlock them — PRs welcome. |
| **Now Playing for browsers** | **Partial.** Apple gated MediaRemote behind a private entitlement in macOS 15.4, confirmed still gated on 26.5. Earshot falls back to AppleScript, which covers Music and Spotify but not browser tabs. |
| **Magic Mouse / Keyboard battery** | **Untested** — I don't own any. The code path exists via `system_profiler`. Please report back. |

## How it works

AirPods continuously broadcast an Apple "proximity pairing" BLE advertisement —
manufacturer ID `0x004C`, message type `0x07`. The first nine bytes are
plaintext:

```
07 19 | 01 27 20 2b 99 8f 11 00 09 | <16 bytes, encrypted>
              └──┬──┘  └┬┘  └┬┘
                 │      │    └─ case battery + charging flags
                 │      └─ 0x99 → left 90%, right 90%
                 └─ 0x2027 → AirPods Pro (3rd generation)
```

Battery nibbles are tens of a percent; `0x0F` means *not reported* — which
Earshot renders as `—`, never as `0%`, because a healthy battery and an unknown
one are different facts.

Four sources are merged into one device list:

- **BLE adverts** — the only battery source while a device is disconnected
- **`system_profiler`** — authoritative while connected: exact, side-labelled
- **`IOBluetooth`** — pairing and live connection state
- **Companion reports** — iPhone/iPad/Watch, via iCloud Drive

Only the 25-byte payload with a model id in Apple's `0x20xx` audio range is
trusted. A shorter 17-byte variant exists and decodes, under the same offsets,
to convincing nonsense — one live capture read as *"L 80%, R 20%, lid=15"* from
bytes that plainly are not those fields, and another produced model `0x8ADF`.
Both are now rejected rather than shown.

Precedence rules live in
[`DeviceMerge`](Sources/EarshotKit/Devices/DeviceMerge.swift) as a pure
function, so they're unit-tested without hardware. The subtle one: adverts round
to 10%, so they must never overwrite a connected device's exact reading, and
when two peripherals share a model the *nearest* wins — otherwise a stranger's
identical AirPods can overwrite your battery. That was a real bug, found against
live hardware, and it has a regression test.

**No private frameworks are used.** Everything is supported API, which is why
this survives OS updates.

Deeper notes: [docs/PROTOCOL.md](docs/PROTOCOL.md) ·
[docs/FEASIBILITY.md](docs/FEASIBILITY.md) ·
[docs/CROSS-DEVICE.md](docs/CROSS-DEVICE.md)

## Building and testing

```sh
swift build              # library, app and CLI
swift test               # 56 tests, no hardware required
./Scripts/build-app.sh   # assemble Earshot.app

# Verifies the real status item, popover, HUD, CoreAudio and BLE stack:
./build/Earshot.app/Contents/MacOS/Earshot --selftest
```

The test suite runs from packet fixtures captured from real hardware, so the
parser is testable on any machine — including CI, which has no Bluetooth.

```
Sources/EarshotKit    core library — BLE, devices, audio, history, mobile (no UI)
Sources/EarshotApp    menu bar app, notch island, HUD, dashboard
Sources/EarshotCLI    the earshot command
Tests/                56 tests
```

## Contributing

Bug reports from hardware I don't own are genuinely the most useful thing —
especially Beats, AirPods Max, and Magic peripherals. `earshot watch` prints
raw adverts; paste the output into an issue.

The unknown bits of the protocol are marked in
[docs/PROTOCOL.md](docs/PROTOCOL.md); status-byte bit meanings in particular are
guesswork and would benefit from a capture matrix.

## Licence and credit

MIT — see [LICENSE](LICENSE).

Not affiliated with Apple. "AirPods" and "AirBuddy" belong to their respective
owners; no AirBuddy code or assets were used. The proximity-pairing message
layout is community-documented reverse engineering, re-verified here against
real hardware.
