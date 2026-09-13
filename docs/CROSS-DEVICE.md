# Cross-device battery (iPhone, iPad, Apple Watch)

Earshot can show the battery of your other Apple devices next to your AirPods.
It takes about two minutes to set up, once, per device.

## Why it needs setup

AirPods are easy: they broadcast their battery in the **plaintext** prefix of a
Bluetooth LE advertisement, and anyone in range can read it. That is the whole
basis of this app.

iPhone, iPad and Apple Watch are not easy. They broadcast over Continuity, and
that payload is **encrypted** with keys synced through your iCloud keychain. No
third-party app can read it. Two things were checked directly before settling on
this approach:

- **The Continuity broadcast** — encrypted, keys unavailable.
- **The Find My cache** (`~/Library/Caches/com.apple.findmy.fmipcore/`) — a
  binary plist wrapping an `encryptedData` blob. Measured entropy **7.99 of 8.0
  bits per byte**: solid ciphertext, key held by Apple.

Both are closed. So instead of reverse-engineering something brittle that breaks
on the next macOS update, **the device reports its own battery**. An iOS
Shortcut writes a small JSON file to iCloud Drive; Earshot reads it. Supported
APIs on both ends, and it works from anywhere rather than only in Bluetooth
range.

The trade-off is honest: readings are as fresh as the automation's schedule, not
live. AirBuddy does this better. This is the best a third-party app can do
without private entitlements.

## Setup

### 1. Create the folder

In Earshot: **Settings → iPhone, iPad and Apple Watch → Create folder**.

That makes `iCloud Drive/Earshot/`. Confirm it appears in the Files app on your
iPhone before continuing.

### 2. Build the Shortcut on your iPhone

Open **Shortcuts → + → New Shortcut**, name it `Report Battery`, and add these
four actions in order:

| # | Action | Setting |
|---|---|---|
| 1 | **Get Battery Level** | — |
| 2 | **Get Device Details** | choose **Device Name** |
| 3 | **Text** | the JSON below |
| 4 | **Save File** | destination `iCloud Drive/Earshot/`, filename `iphone.json`, **Overwrite If File Exists → On** |

For the **Text** action, type this exactly, inserting the two magic variables
where shown — `Device Name` from step 2, `Battery Level` from step 1:

```json
{"name":"‹Device Name›","kind":"phone","battery":‹Battery Level›,"updated":"‹Current Date›"}
```

Three details that matter:

- **`battery` must not be quoted.** `Battery Level` returns a number; wrapping it
  in quotes makes the JSON fail to parse.
- Shortcuts' `Battery Level` is a **fraction on some iOS versions** (`0.72`) and
  a percentage on others (`72`). If your device shows up at 0%, add a
  **Calculate** action multiplying by 100 and use its result.
- Set `"kind"` to `phone`, `tablet`, or `watch`. If you omit it, Earshot guesses
  from the device name, which usually works.

For **Current Date**, insert the *Current Date* variable and set its format to
**ISO 8601**. If that's awkward, drop the `"updated"` field entirely — Earshot
falls back to the file's modification time.

Use a **different filename per device** (`iphone.json`, `ipad.json`,
`watch.json`), or they will overwrite each other.

### 3. Run it automatically

Shortcuts → **Automation → + → Personal Automation**. Good triggers:

- **Time of Day**, every hour — steady baseline
- **Charger connected** / **disconnected** — catches the interesting moments
- **Low Power Mode** — catches the important one

Set **Run Immediately** and turn **Notify When Run** off, or you'll get a banner
every hour.

> Apple Watch has no Shortcuts automation of its own. Run the shortcut from the
> Watch app manually, or accept that the Watch updates less often.

### 4. Check it

```sh
earshot status --scan 0 | grep -i iphone
```

Your iPhone should appear with its battery. It will also show in the dashboard
and the notch island, tagged **via Shortcut**.

## File format

One JSON object per file in `iCloud Drive/Earshot/`:

```json
{
  "name": "Surya's iPhone",
  "kind": "phone",
  "battery": 72,
  "charging": false,
  "updated": "2026-09-13T16:40:00Z"
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Shown in the UI |
| `battery` | yes | Integer 0–100. Anything outside is rejected. |
| `kind` | no | `phone`, `tablet`, `watch`. Guessed from `name` if absent. |
| `charging` | no | Defaults to false |
| `updated` | no | ISO 8601 preferred; falls back to file mtime |

Reports older than **six hours are ignored** — a stale battery reading is worse
than no reading, because it looks current.

## Troubleshooting

**Device doesn't appear.** Check the file actually reached the Mac:

```sh
ls -la ~/Library/Mobile\ Documents/com~apple~CloudDocs/Earshot/
cat ~/Library/Mobile\ Documents/com~apple~CloudDocs/Earshot/iphone.json
```

If the file isn't there, iCloud hasn't synced — open the Files app on the iPhone
and confirm the save worked. If it is there but Earshot ignores it, the JSON is
probably malformed: run it through `python3 -m json.tool` to check.

**Shows 0%.** `Battery Level` returned a fraction. Multiply by 100 (see above).

**Was working, now stale.** The automation stopped running. iOS suspends
automations that fail repeatedly; open Shortcuts and run it manually once.

## Anything else

Nothing about this is iOS-specific — any process that writes a conforming JSON
file into that folder will show up. A Linux box, a Raspberry Pi, or a cron job
on another Mac all work the same way.
