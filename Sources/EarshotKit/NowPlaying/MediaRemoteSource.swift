import Foundation

/// Reads Now Playing from the private MediaRemote framework, if it will talk
/// to us. Loaded with `dlopen` so a missing or gated framework degrades to
/// "no data" instead of failing to launch.
///
/// Apple restricted this in macOS 15.4; expect `fetch()` to return nil on
/// current systems and the AppleScript sources to take over.
public struct MediaRemoteSource: NowPlayingSource {
    public let name = "MediaRemote"
    public init() {}

    /// The callback must be `@escaping`: MediaRemote answers asynchronously and
    /// retains the block past the call. Declaring it non-escaping makes Swift
    /// free the block on return, and the later callback lands on freed memory.
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void

    public func fetch() -> NowPlayingInfo? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
        let getInfo = unsafeBitCast(sym, to: GetInfoFn.self)

        // The API is async with no timeout of its own; a semaphore bounds the
        // wait so a gated call cannot hang the caller.
        let sem = DispatchSemaphore(value: 0)
        let box = InfoBox()
        getInfo(DispatchQueue.global(qos: .userInitiated)) { dict in
            box.value = dict
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 1.0) == .success,
              let info = box.value, !info.isEmpty else { return nil }

        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        guard let title, !title.isEmpty else { return nil }
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        return NowPlayingInfo(
            title: title,
            artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String,
            app: "MediaRemote",
            isPlaying: rate > 0
        )
    }

    private final class InfoBox: @unchecked Sendable {
        var value: [String: Any]?
    }
}
