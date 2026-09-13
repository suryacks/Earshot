import Foundation

public struct NowPlayingInfo: Sendable, Equatable, Codable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var app: String
    public var isPlaying: Bool
    /// Album art, when the source can give us one. Spotify exposes a URL over
    /// AppleScript; Music returns raw image data, which is not worth the
    /// round-trip here, so it stays nil there.
    public var artworkURL: URL?

    public init(title: String, artist: String? = nil, album: String? = nil,
                app: String, isPlaying: Bool, artworkURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.app = app
        self.isPlaying = isPlaying
        self.artworkURL = artworkURL
    }

    public var summary: String {
        if let artist, !artist.isEmpty { return "\(title) — \(artist)" }
        return title
    }
}

public protocol NowPlayingSource: Sendable {
    var name: String { get }
    func fetch() -> NowPlayingInfo?
}

/// Resolves Now Playing through whichever source works on this machine.
///
/// MediaRemote is preferred because it sees every app, but Apple gated it
/// behind a private entitlement in macOS 15.4 and it may return nothing. The
/// AppleScript sources are narrower - they only know about Music and Spotify,
/// and need an Automation permission grant - but they are supported API and
/// were verified working during research. Probing happens once, lazily.
public final class NowPlayingResolver: @unchecked Sendable {
    private let sources: [NowPlayingSource]
    private var chosen: NowPlayingSource?
    private var probed = false
    private let lock = NSLock()

    public init(sources: [NowPlayingSource]? = nil) {
        self.sources = sources ?? [
            MediaRemoteSource(),
            AppleScriptMusicSource(app: "Spotify"),
            AppleScriptMusicSource(app: "Music"),
        ]
    }

    public var activeSourceName: String? {
        lock.lock(); defer { lock.unlock() }
        return chosen?.name
    }

    /// Falls back per-call rather than sticking to a dead source: the user may
    /// switch from Spotify to Music mid-session.
    public func fetch() -> NowPlayingInfo? {
        lock.lock()
        let preferred = chosen
        lock.unlock()

        if let preferred, let info = preferred.fetch() { return info }
        for source in sources {
            if let info = source.fetch() {
                lock.lock(); chosen = source; probed = true; lock.unlock()
                return info
            }
        }
        lock.lock(); probed = true; lock.unlock()
        return nil
    }
}
