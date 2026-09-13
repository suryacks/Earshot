# Apple Proximity Pairing BLE Message (`0x07`)

Implementation reference for the parser. Layouts below are the community
consensus for this message type, **annotated with what this project actually
confirmed on-device** — treat unconfirmed fields as hypotheses until a fixture
proves them.

## Frame

AirPods advertise as BLE manufacturer-specific data under Apple's company ID:

```
Company ID : 0x004C  (little-endian on the wire: 4C 00)
Msg type   : 0x07    (proximity pairing)
Msg length : 0x19 (25) typical · 0x11 (17) short variant — branch on this
```

Payload = first **9 bytes plaintext**, trailing **16 bytes encrypted**. Only the
plaintext prefix is needed; do not attempt to decrypt the tail.

## Plaintext prefix

| Off | Field | Notes |
|---|---|---|
| 0 | Prefix / paired status | `0x01` observed |
| 1–2 | **Device model, little-endian** | ✅ `27 20` → `0x2027` = AirPods Pro. Matches the Product ID from `system_profiler` exactly. |
| 3 | Status flags | in-ear, primary bud, lid state. Bit meanings **not yet confirmed** — needs a capture matrix. |
| 4 | **Pod battery** | ✅ high/low nibble. `0x99` → 9 and 9 → 90% / 90% (actual 90% / 92%). |
| 5 | Case battery + charging | low nibble = case level, high nibble = charging bits. `0x8f` seen with `f` = unknown/not reported. |
| 6 | Lid-open counter | increments per lid open; drives the HUD trigger |
| 7 | Device colour | `0x00` observed |
| 8 | Connection state | `0x09` observed |

### Battery nibble encoding
Value × 10 = percent. `0xF` means **unknown — render as "—", never as 0%.**

Which nibble is left vs. right depends on the primary-bud bit in byte 3, so the
pods swap as you wear one at a time. Resolve byte 3 before trusting L/R labels;
until then, cross-check against `system_profiler`, which labels them explicitly.

## Captured fixtures

Use these as the first parser unit tests. Ground truth from `system_profiler`
at capture time: **L 90% · R 92% · case 40%**, AirPods Pro, `0x2027`.

```
# 25-byte payload — AirPods Pro, connected, RSSI -44
07190127202b998f110009095a5cff4652e7000000761cb2372224

# same device moments later, RSSI -45
07190127202b998f110009095a5cff4652e7000000661cbbeacc5d

# 17-byte short variant — different nearby device, model 0x2029, RSSI -41
07110629200b28ffff510b000000007df20200
```

## Parsing rules

1. **Branch on payload length first.** The 17-byte variant does not share the
   25-byte field layout. Parse defensively; never index past `count`.
2. **Filter to our devices.** A café will produce dozens of these. Match on
   model ID plus a stable identifier — see the paired-host lead below.
3. **Debounce the lid counter.** Packets repeat several times per second (26 in
   20 s from one device). Fire the HUD on *change*, not on arrival.
4. **`0xF` is not zero.** A dead battery and an unreported battery must not look
   the same to the user.
5. **Cross-check when connected.** While the device is connected,
   `system_profiler` is authoritative and per-side labelled; prefer it and use
   BLE for the disconnected/lid-open case.

## Open question: device ownership

In both 25-byte captures the bytes `46 52 e7` appear inside the nominally
encrypted region and match the tail of this Mac's Bluetooth controller address,
`84:2F:57:46:52:E7`.

If that is a paired-host identifier rather than ciphertext, it solves rule 2
cleanly — you can recognise your own AirPods with no pairing step and no
decryption. **Unconfirmed.** Verify by capturing the same AirPods from a second
Mac: if those bytes track the *observing* host, the theory is wrong; if they
track the *paired* host, it holds.
