// [Intent] Common protocol and models decoupling UI components from underlying media engines
import Foundation
import CoreStorage

public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case failed(String)
}

public struct TrackOption: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let language: String?
    public let isSelected: Bool

    public init(id: Int, name: String, language: String? = nil, isSelected: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isSelected = isSelected
    }
}

public protocol MediaPlayerProtocol: AnyObject, Sendable {
    var state: PlaybackState { get }
    var currentPosition: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var playbackRate: Float { get set }
    var currentItem: MediaItem? { get }
    var availableAudioTracks: [TrackOption] { get }
    var availableSubtitleTracks: [TrackOption] { get }

    func load(item: MediaItem) async throws
    func play()
    func pause()
    func togglePlayPause()
    func seek(to position: TimeInterval)
    func selectAudioTrack(index: Int)
    func selectSubtitleTrack(index: Int)
    func releaseResources()
}
