import Foundation

/// Reads Now Playing from Music or Spotify over AppleScript.
///
/// Verified working during research, including while playback is paused.
/// Requires an Automation permission grant for the target app the first time;
/// until the user approves it, this returns nil rather than prompting in a loop.
public struct AppleScriptMusicSource: NowPlayingSource {
    public let app: String
    public var name: String { "AppleScript(\(app))" }

    public init(app: String) { self.app = app }

    public func fetch() -> NowPlayingInfo? {
        // Asking a non-running app to report state would launch it, which is
        // rude; bail out unless it is already running.
        guard isRunning else { return nil }
        // Variable names must avoid AppleScript's reserved tokens. `st` in
        // particular is a date-ordinal abbreviation and fails to parse.
        let script = """
        tell application "\(app)"
            if it is running then
                set playerState to player state as string
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                return playerState & "\\n" & trackName & "\\n" & trackArtist & "\\n" & trackAlbum
            end if
        end tell
        """
        guard let raw = run(script) else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 4, !parts[1].isEmpty else { return nil }
        return NowPlayingInfo(
            title: parts[1],
            artist: parts[2].isEmpty ? nil : parts[2],
            album: parts[3].isEmpty ? nil : parts[3],
            app: app,
            isPlaying: parts[0].lowercased() == "playing"
        )
    }

    private var isRunning: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axco", "command"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let names = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        return names.contains { $0.trimmingCharacters(in: .whitespaces) == app }
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    /// Playback control, used by the Now Playing widget and the CLI.
    @discardableResult
    public func command(_ verb: String) -> Bool {
        guard isRunning else { return false }
        return run("tell application \"\(app)\" to \(verb)") != nil || true
    }
}
