import Foundation
import EarshotKit

let version = "0.1.0"

// Streaming commands (`watch`, `find`) are usually piped or tailed. Default
// block buffering would withhold their output until the buffer filled or the
// process exited, which never happens for a long-running stream.
setvbuf(stdout, nil, _IOLBF, 0)

func err(_ s: String) -> Never {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    exit(1)
}

func printJSON(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let d = try? JSONSerialization.data(withJSONObject: value,
                                              options: [.prettyPrinted, .sortedKeys]) else {
        err("could not encode JSON")
    }
    print(String(decoding: d, as: UTF8.self))
}

func deviceJSON(_ d: DeviceState) -> [String: Any] {
    var o: [String: Any] = [
        "id": d.id,
        "name": d.name,
        "kind": d.kind.rawValue,
        "connected": d.isConnected,
        "paired": d.isPaired,
        "charging": d.isCharging,
        "battery_from_advert": d.batteryFromAdvert,
    ]
    if let v = d.address { o["address"] = v }
    if let v = d.productID { o["product_id"] = String(format: "0x%04X", v) }
    if let v = d.left { o["left"] = v }
    if let v = d.right { o["right"] = v }
    if let v = d.caseBattery { o["case"] = v }
    if let v = d.single { o["battery"] = v }
    if let v = d.rssi { o["rssi"] = v }
    if let v = d.minimumBattery { o["minimum"] = v }
    if d.lastSeen > .distantPast {
        o["last_seen"] = ISO8601DateFormatter().string(from: d.lastSeen)
    }
    return o
}

let usage = """
earshot \(version) — AirPods and Bluetooth audio from the command line

USAGE
  earshot <command> [options]

COMMANDS
  status [--json] [--all]   Battery and connection for your devices
  devices [--json]          Alias for status
  connect <name>            Connect a paired Bluetooth device
  disconnect <name>         Disconnect a paired Bluetooth device
  toggle <name>             Connect if disconnected, else disconnect
  audio [--json]            List audio devices and current defaults
  output <name>             Set the default audio output
  input <name>              Set the default audio input
  nowplaying [--json]       Current track, if any
  find <name>               Live proximity meter for locating a device
  history <name> [--hours N]  Battery history and time-to-empty estimate
  watch [--raw]             Stream BLE adverts as they arrive
  version                   Print version

OPTIONS
  --json                    Machine-readable output
  --all                     Also list nearby devices not paired with this Mac
  --scan <seconds>          BLE scan window for status (default 4)
  --no-color                Disable ANSI colour

NOTES
  Disconnected devices only report battery over Bluetooth LE, so commands that
  read battery run a short scan first. Grant Bluetooth permission to your
  terminal when macOS asks, or those devices will show no data.
"""

// MARK: - Argument parsing

var args = Array(CommandLine.arguments.dropFirst())
let wantJSON = args.contains("--json")
if args.contains("--no-color") { Format.useColor = false }
var scanSeconds: TimeInterval = 4
if let i = args.firstIndex(of: "--scan"), i + 1 < args.count, let v = TimeInterval(args[i + 1]) {
    scanSeconds = max(0, min(30, v))
    args.removeSubrange(i...(i + 1))
}
let showRaw = args.contains("--raw")
// Strangers' AirPods are noise by default; --all opts in when you actually
// want to find something to connect to.
let showAll = args.contains("--all")
args.removeAll { $0 == "--raw" || $0 == "--all" }
var hours = 12.0
if let i = args.firstIndex(of: "--hours"), i + 1 < args.count, let v = Double(args[i + 1]) {
    hours = max(0.1, min(24 * 30, v))
    args.removeSubrange(i...(i + 1))
}
args.removeAll { $0 == "--json" || $0 == "--no-color" }

guard let command = args.first else {
    print(usage)
    exit(0)
}
let operand = args.dropFirst().joined(separator: " ")

func requireOperand(_ what: String) -> String {
    guard !operand.isEmpty else { err("error: expected \(what)\n\nTry: earshot \(command) <\(what)>") }
    return operand
}

// MARK: - Commands

@MainActor
func runStatus() {
    let collector = Collector()
    let devices = collector.snapshot(scanFor: scanSeconds, quiet: wantJSON)

    if wantJSON {
        printJSON([
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "bluetooth": String(describing: collector.scannerState()),
            "devices": (showAll ? devices : devices.filter(\.isPaired)).map(deviceJSON),
        ])
        return
    }

    if collector.scannerState() == .unauthorized {
        FileHandle.standardError.write(
            "warning: Bluetooth permission denied, so disconnected devices cannot report battery.\n"
                .data(using: .utf8)!)
    }
    guard !devices.isEmpty else {
        print(Format.dim("No Bluetooth devices found."))
        return
    }
    let known = devices.filter(\.isPaired)
    let nearby = devices.filter { !$0.isPaired }
    for d in known { print(Format.deviceLine(d)) }
    if showAll {
        if nearby.isEmpty {
            print()
            print(Format.dim("No unpaired devices broadcasting nearby."))
        } else {
            print()
            print(Format.dim("Nearby, not paired with this Mac:"))
            for d in nearby { print(Format.deviceLine(d)) }
        }
    } else if !nearby.isEmpty {
        print()
        print(Format.dim("\(nearby.count) nearby device\(nearby.count == 1 ? "" : "s") hidden — use --all to show"))
    }
}

@MainActor
func runConnectionCommand(_ verb: String) {
    let query = requireOperand("device name")
    guard let device = BluetoothControl.device(named: query) else {
        let names = BluetoothControl.pairedDevices().map(\.name).sorted()
        err("error: no paired device matching \"\(query)\"\n\nPaired devices:\n  " +
            names.joined(separator: "\n  "))
    }
    let address = BluetoothControl.normalize(device.addressString ?? "")
    let name = device.name ?? query
    let ok: Bool
    switch verb {
    case "connect": ok = BluetoothControl.connect(address: address)
    case "disconnect": ok = BluetoothControl.disconnect(address: address)
    default: ok = BluetoothControl.toggle(address: address)
    }
    if ok {
        print("\(verb == "disconnect" ? "Disconnected" : "Connected") \(Format.bold(name))")
    } else {
        err("error: could not \(verb) \(name)")
    }
}

func runAudio() {
    let outputs = AudioRouter.outputs()
    let inputs = AudioRouter.inputs()
    let defOut = AudioRouter.defaultOutput()
    let defIn = AudioRouter.defaultInput()

    if wantJSON {
        printJSON([
            "default_output": defOut.map { ["name": $0.name, "uid": $0.uid] } as Any,
            "default_input": defIn.map { ["name": $0.name, "uid": $0.uid] } as Any,
            "outputs": outputs.map { ["name": $0.name, "uid": $0.uid, "transport": $0.transport] },
            "inputs": inputs.map { ["name": $0.name, "uid": $0.uid, "transport": $0.transport] },
        ])
        return
    }
    print(Format.bold("Output"))
    for d in outputs {
        let mark = d.id == defOut?.id ? Format.c("●", "32") : Format.dim("○")
        print("  \(mark) \(d.name) \(Format.dim("(\(d.transport))"))")
    }
    print(Format.bold("\nInput"))
    for d in inputs {
        let mark = d.id == defIn?.id ? Format.c("●", "32") : Format.dim("○")
        print("  \(mark) \(d.name) \(Format.dim("(\(d.transport))"))")
    }
}

func runSetAudio(input: Bool) {
    let query = requireOperand("audio device name")
    guard let device = AudioRouter.find(query, input: input) else {
        let pool = input ? AudioRouter.inputs() : AudioRouter.outputs()
        err("error: no \(input ? "input" : "output") device matching \"\(query)\"\n\nAvailable:\n  " +
            pool.map(\.name).joined(separator: "\n  "))
    }
    let ok = input ? AudioRouter.setDefaultInput(device) : AudioRouter.setDefaultOutput(device)
    if ok { print("\(input ? "Input" : "Output") → \(Format.bold(device.name))") }
    else { err("error: could not set \(input ? "input" : "output") to \(device.name)") }
}

func runNowPlaying() {
    let info = NowPlayingResolver().fetch()
    if wantJSON {
        guard let info else { printJSON(["playing": false]); return }
        printJSON([
            "playing": info.isPlaying,
            "title": info.title,
            "artist": info.artist as Any,
            "album": info.album as Any,
            "app": info.app,
            "artwork": info.artworkURL?.absoluteString as Any,
        ])
        return
    }
    guard let info else {
        print(Format.dim("Nothing playing."))
        return
    }
    print("\(info.isPlaying ? "▶" : "⏸") \(Format.bold(info.title))")
    if let a = info.artist { print("  \(a)") }
    print(Format.dim("  via \(info.app)"))
}

@MainActor
func runFind() {
    let query = requireOperand("device name")
    let scanner = BLEScanner()
    var best = -127
    print("Searching for \(Format.bold(query))… \(Format.dim("Ctrl-C to stop"))\n")

    scanner.onObservation = { obs in
        guard obs.message.model.name.lowercased().contains(query.lowercased())
                || String(format: "0x%04x", obs.message.model.id).contains(query.lowercased())
        else { return }
        best = max(best, obs.rssi)
        let pct = Format.proximity(obs.rssi)
        let label: String
        switch pct {
        case 80...: label = Format.c("very close", "32")
        case 55..<80: label = Format.c("close", "32")
        case 30..<55: label = Format.c("nearby", "33")
        default: label = Format.c("far", "31")
        }
        let line = "\r\(Format.bar(pct, width: 24)) \(String(format: "%3d", pct))  \(obs.rssi) dBm  \(label)   "
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
    }
    scanner.start()
    RunLoop.current.run()
}

@MainActor
func runWatch() {
    let scanner = BLEScanner()
    print(Format.dim("Streaming Apple proximity-pairing adverts. Ctrl-C to stop.\n"))
    scanner.onObservation = { obs in
        let m = obs.message
        let time = DateFormatter.localizedString(from: obs.date, dateStyle: .none, timeStyle: .medium)
        var bits: [String] = []
        if let l = m.leftBattery { bits.append("L \(l)%") }
        if let r = m.rightBattery { bits.append("R \(r)%") }
        if let c = m.caseBattery { bits.append("case \(c)%") }
        if m.leftCharging || m.rightCharging || m.caseCharging { bits.append("⚡︎") }
        print("\(Format.dim(time))  \(Format.bold(m.model.name))  \(bits.joined(separator: " "))  \(Format.dim("\(obs.rssi) dBm  lid=\(m.lidCounter)"))")
        if showRaw {
            print(Format.dim("             raw: \(m.rawPayload.hexString)  status=0x\(String(format: "%02x", m.rawStatus))"))
        }
    }
    scanner.onLidOpened = { obs in
        print(Format.c("  ↑ lid opened — \(obs.message.model.name)", "36"))
    }
    scanner.start()
    RunLoop.current.run()
}

@MainActor
func runHistory() {
    let query = requireOperand("device name")
    guard let store = BatteryStore() else { err("error: could not open history database") }
    let devices = SystemProfiler.snapshot()
    guard let device = devices.first(where: { $0.name.lowercased().contains(query.lowercased()) }) else {
        err("error: no device matching \"\(query)\"")
    }
    let since = Date().addingTimeInterval(-hours * 3600)
    let samples = store.history(deviceID: device.id, since: since)

    if wantJSON {
        printJSON([
            "device": device.name,
            "hours": hours,
            "samples": samples.map {
                ["at": ISO8601DateFormatter().string(from: $0.date),
                 "level": $0.level, "charging": $0.charging]
            },
            "seconds_to_empty": store.timeToEmpty(deviceID: device.id) as Any,
        ])
        return
    }
    print(Format.bold(device.name))
    guard !samples.isEmpty else {
        print(Format.dim("No history yet. Earshot records battery while it runs — leave the app open for a while."))
        return
    }
    for s in samples.suffix(24) {
        let t = DateFormatter.localizedString(from: s.date, dateStyle: .none, timeStyle: .short)
        print("  \(Format.dim(t))  \(Format.bar(s.level)) \(Format.level(s.level))\(s.charging ? Format.c(" ⚡︎", "33") : "")")
    }
    if let eta = store.timeToEmpty(deviceID: device.id) {
        print("\n  Estimated \(Format.bold(Format.duration(eta))) until empty at the current drain rate.")
    }
}

// MARK: - Dispatch

switch command {
case "status", "devices", "list": MainActor.assumeIsolated { runStatus() }
case "connect", "disconnect", "toggle": MainActor.assumeIsolated { runConnectionCommand(command) }
case "audio": runAudio()
case "output": runSetAudio(input: false)
case "input": runSetAudio(input: true)
case "nowplaying", "np": runNowPlaying()
case "find": MainActor.assumeIsolated { runFind() }
case "watch": MainActor.assumeIsolated { runWatch() }
case "history": MainActor.assumeIsolated { runHistory() }
case "version", "--version", "-v": print("earshot \(version)")
case "help", "--help", "-h": print(usage)
default:
    err("error: unknown command \"\(command)\"\n\nRun `earshot help` for usage.")
}
