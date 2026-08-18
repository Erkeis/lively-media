// [Intent] MPNowPlayingInfoCenter and MPRemoteCommandCenter bridge for Lock Screen, Dynamic Island, and CarPlay
import Foundation
import MediaPlayer
import CoreStorage

public protocol NowPlayingManagerProtocol: AnyObject, Sendable {
    func updateNowPlaying(
        item: MediaItem,
        currentPosition: TimeInterval,
        duration: TimeInterval,
        playbackRate: Float,
        artworkData: Data?
    )
    func clearNowPlaying()
    func configureRemoteCommands(
        onPlay: @escaping @MainActor @Sendable () -> Void,
        onPause: @escaping @MainActor @Sendable () -> Void,
        onToggle: @escaping @MainActor @Sendable () -> Void,
        onSkipForward: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        onSkipBackward: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        onSeek: @escaping @MainActor @Sendable (TimeInterval) -> Void
    )
}

public final class NowPlayingManager: NowPlayingManagerProtocol, @unchecked Sendable {
    public static let shared = NowPlayingManager()

    public init() {}

    public func updateNowPlaying(
        item: MediaItem,
        currentPosition: TimeInterval,
        duration: TimeInterval,
        playbackRate: Float,
        artworkData: Data? = nil
    ) {
        #if os(iOS)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: Double(playbackRate)
        ]

        if let artist = item.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = item.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        if let data = artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    public func clearNowPlaying() {
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    public func configureRemoteCommands(
        onPlay: @escaping @MainActor @Sendable () -> Void,
        onPause: @escaping @MainActor @Sendable () -> Void,
        onToggle: @escaping @MainActor @Sendable () -> Void,
        onSkipForward: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        onSkipBackward: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        onSeek: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in onPlay() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in onToggle() }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { event in
            let interval: TimeInterval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor in onSkipForward(interval) }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { event in
            let interval: TimeInterval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor in onSkipBackward(interval) }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                let pos = posEvent.positionTime
                Task { @MainActor in onSeek(pos) }
                return .success
            }
            return .commandFailed
        }
        #endif
    }
}
