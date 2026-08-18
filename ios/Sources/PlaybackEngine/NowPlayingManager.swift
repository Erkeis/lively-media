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
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onToggle: @escaping @Sendable () -> Void,
        onSkipForward: @escaping @Sendable (TimeInterval) -> Void,
        onSkipBackward: @escaping @Sendable (TimeInterval) -> Void,
        onSeek: @escaping @Sendable (TimeInterval) -> Void
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
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onToggle: @escaping @Sendable () -> Void,
        onSkipForward: @escaping @Sendable (TimeInterval) -> Void,
        onSkipBackward: @escaping @Sendable (TimeInterval) -> Void,
        onSeek: @escaping @Sendable (TimeInterval) -> Void
    ) {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            onPlay()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            onToggle()
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                onSkipForward(skipEvent.interval)
            } else {
                onSkipForward(10)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                onSkipBackward(skipEvent.interval)
            } else {
                onSkipBackward(10)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                onSeek(posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
        #endif
    }
}
