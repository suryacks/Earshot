# Scope

> **Status — v0.1.0 shipped.** Tier A and most of Tier B are implemented and
> working; the CLI, proximity finder, battery history and per-app audio rules
> are all in. Not implemented: desktop widgets (needs an Xcode appex target),
> ANC control and mobile-device battery (both blocked — see FEASIBILITY §9,
> §10). Shortcuts support landed as a URL scheme rather than App Intents,
> because SPM cannot build an extension target.
>
> This document is kept as the original plan, for comparison against what the
> build actually cost.

Feature-by-feature plan. Every row is graded by the probe evidence in
[FEASIBILITY.md](FEASIBILITY.md) — nothing here is graded from intuition.

Effort is in focused days for one developer already fluent in Swift/AppKit.

---

## Part 1 — AirBuddy 3 parity

### Tier A: core, all-green dependencies

| Feature | Depends on | Effort | Risk |
|---|---|---|---|
| Lid-open battery HUD | BLE `0x07` ✅ | 4–5 d | Low |
| Dashboard (all devices, battery, connect) | BLE + `system_profiler` ✅ | 4 d | Low |
| Connect / disconnect from UI | `IOBluetooth` ✅ | 1 d | Low |
| Battery alerts + notifications | above | 1 d | Low |
| Audio output routing | CoreAudio ✅ | 1 d | Low |
| **Audio Input Lock** | CoreAudio ✅ | 1 d | Low |
| Menu bar extra | AppKit | 1 d | Low |
| Launch at login | `SMAppService` | 0.5 d | Low |

Tier A is the real product. ~14 days, and every dependency is verified working.

### Tier B: public frameworks, more surface area

| Feature | Depends on | Effort | Risk |
|---|---|---|---|
| Desktop widgets (battery, device) | WidgetKit | 3 d | Low |
| Shortcuts actions | App Intents | 2 d | Low |
| AppleScript dictionary | `NSScriptCommand` | 2 d | Low |
| Global hotkeys | Carbon/`CGEventTap` | 1 d | Low |
| Focus Filters | `INFocusStatusCenter` | 1 d | Low |
| Liquid Glass styling | SwiftUI on Tahoe | 2 d | Low |
| Action HUD (incl. notch layout) | AppKit + `safeAreaInsets` | 4 d | Med |

### Tier C: contested

| Feature | Status | Call |
|---|---|---|
| Now Playing | MediaRemote unresolved; AppleScript fallback proven | Build behind a `NowPlayingSource` protocol. 3–5 d. |
| Magic Handoff | Private path blocked; public workaround unproven | Spike 1 d before committing. |
| Magic peripheral battery | Untested, no hardware | 1 d once hardware is present. |
| Independent case status | Extends `0x07` parsing | 1–2 d, folds into Tier A. |

### Tier D: recommend cutting from v1

| Feature | Why |
|---|---|
| ANC / Transparency / Spatial Audio **control** | Needs blocked private L2CAP path. Reading mode may be possible; setting is not. |
| iPhone / iPad / Watch battery | Encrypted Continuity payloads. See FEASIBILITY §10. |

---

## Part 2 — additions worth making

AirBuddy is mature; cloning it exactly produces a strictly worse AirBuddy. These
five are where a fresh build can actually be *better*, and four of the five ride
on data the probes already prove we can read.

### 1. Proximity finder — "where did I leave them?" ★ best idea here
We already receive RSSI on every `0x07` packet (`-44`, `-45`, `-41` in the
probe). Render it as a live hot/cold meter with an optional audio cue and you
have a Find-My-style locator for AirPods that are out of the case, in the couch,
and *not connected*. AirBuddy does not do this. Nearly free — the data is
already flowing through the scanner.
**Effort: 2 d. Risk: low.**

### 2. Battery history and drain-rate prediction
Log every battery reading to SQLite. Show a real discharge curve and a derived
"≈37 min left at this drain rate" instead of a bare percentage. Also surfaces
long-term capacity fade — genuinely useful given how notoriously AirPods
batteries degrade after ~18 months.
**Effort: 3 d. Risk: low.**

### 3. Per-app audio rules
A natural extension of Audio Input Lock, and the feature I'd personally want
most: *"when Zoom is frontmost, force input to the Shure and output to AirPods;
when Logic opens, switch to the interface."* Rules engine over the CoreAudio
property listener already required for Input Lock.
**Effort: 3 d. Risk: low.**

### 4. `earshot` CLI with JSON output
`earshot status --json` → battery, connection state, audio route for every
device. Makes the whole thing scriptable from the shell, usable in a status bar
(tmux, Sketchybar, Übersicht), and trivially testable in CI. The daemon already
holds the state; this is a thin socket client.
**Effort: 1.5 d. Risk: low.**

### 5. Battery-health report
Aggregate #2 over months into a "your left bud now holds ~78% of its original
charge" report. Hard to find anywhere else, and the data collection is free once
#2 exists.
**Effort: 2 d. Risk: low — but needs months of data before it says anything.**

---

## Suggested build order

**Milestone 1 — prove the core (~2 weeks).** BLE scanner → device model →
lid-open HUD → connect/disconnect. Ship it to yourself. If the HUD feels good,
the project is real.

**Milestone 2 — daily driver (~1 week).** Dashboard, menu bar, battery alerts,
audio routing, Audio Input Lock, launch at login.

**Milestone 3 — differentiate (~1 week).** Proximity finder, battery history,
CLI. This is where it stops being a clone.

**Milestone 4 — surface area (~2 weeks).** Widgets, Shortcuts, AppleScript,
hotkeys, Focus filters, Action HUD.

**Milestone 5 — contested.** Now Playing, Magic Handoff, per-app audio rules.

Roughly 6–7 weeks of focused work for something genuinely nicer than AirBuddy on
the axes that matter to one user. Milestone 1 alone is a usable tool.

---

## Architecture sketch

```
                 ┌─────────────────────────────────┐
                 │        EarshotKit (SPM)         │  ← all logic, no UI,
                 ├─────────────────────────────────┤    unit-testable
  CoreBluetooth ─┤ BLEScanner → ProximityMessage   │
                 │                  ↓              │
   IOBluetooth ──┤ DeviceRegistry (merges sources) │──→ AsyncStream<DeviceState>
system_profiler ─┤        ↑                        │
                 │ BatteryStore (SQLite history)   │
     CoreAudio ──┤ AudioRouter · InputLock         │
                 └─────────────────────────────────┘
                          ↓            ↓         ↓
                    Earshot.app    Widgets    earshot CLI
```

Three rules that matter:

1. **No private frameworks in v1.** Every Tier A/B feature has a verified public
   path. Staying clean keeps notarization simple and the app resilient across OS
   updates. Revisit only if Magic Handoff proves impossible otherwise.
2. **All logic in `EarshotKit`.** The BLE parser is the highest-value, most
   testable component — feed it captured packet fixtures and assert decoded
   battery. The probe already produced the first fixtures.
3. **One state stream.** `DeviceRegistry` merges BLE, IOBluetooth and
   `system_profiler` into a single `AsyncStream`. HUD, dashboard, widgets and
   CLI are all just subscribers. Prevents the three sources from drifting.

### Packaging notes
- Real `.app` bundle with `NSBluetoothAlwaysUsageDescription` — a bare CLI
  cannot hold the TCC grant.
- Developer ID signature + notarization for a background agent.
- `LSUIElement = true`; menu bar and HUD only, no Dock icon.
- No Mac App Store — background BLE scanning and the daemon model don't fit
  sandbox rules. Irrelevant for personal use.

---

## Legal

Reimplementing functionality for personal use is fine. Do not ship under the
AirBuddy name, do not reuse its assets, and do not redistribute Apple's product
renders — those need original artwork. AirBuddy is a commercial product by
Guilherme Rambo and deserves to stay one; this is a personal build, not a
competitor.
