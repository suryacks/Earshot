import Foundation
import AppKit

/// Playback control for the Now Playing island.
///
/// MediaRemote's `MRMediaRemoteSendCommand` would drive any app, but it is
/// gated (see docs/FEASIBILITY.md §5), so control goes through AppleScript to
/// whichever supported app is actually playing.
public enum MediaControl {
    public enum Command: String, Sendable {
        case playPause, next, previous
    }

    /// Sends `command` to the app currently reported by `resolver`.
    /// Returns false when nothing is playing that we know how to drive, so the
    /// UI can disable its controls rather than pretend they work.
    @discardableResult
    public static func send(_ command: Command, using resolver: NowPlayingResolver) -> Bool {
        guard let info = resolver.fetch() else { return false }
        // Music and Spotify share these verbs; `back track` is Music-only for
        // restart-then-previous, so `previous track` is used for both.
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        return AppleScriptMusicSource(app: info.app).command(verb)
    }
}
