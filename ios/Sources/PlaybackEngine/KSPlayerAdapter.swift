// [Intent] Secondary KSPlayer/Metal fallback adapter for universal containers (MKV, WebM), DTS/Opus audio, and SSA/ASS subtitles
import Foundation
import CoreStorage

public final class KSPlayerAdapter: MediaPlayerProtocol, @unchecked Sendable {
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentPosition: TimeInterval = 0.0
    public private(set) var duration: TimeInterval = 0.0
    public var volume: Float = 1.0
    public var playbackRate: Float = 1.0
    public private(set) var currentItem: MediaItem?
    public private(set) var availableAudioTracks: [TrackOption] = []
    public private(set) var availableSubtitleTracks: [TrackOption] = []

    public var onStateChange: (@Sendable (PlaybackState) -> Void)?
    public var onPositionChange: (@Sendable (TimeInterval, TimeInterval) -> Void)?

    private var playbackTimer: Timer?

    public init() {}

    public func load(item: MediaItem) async throws {
        self.currentItem = item
        self.duration = item.duration > 0 ? item.duration : 120.0
        self.currentPosition = item.playbackPosition
        updateState(.loading)

        // Mock/Simulated KSPlayer pipeline initialization with Metal display layer
        self.availableAudioTracks = [
            TrackOption(id: 0, name: "Default (DTS/FLAC 5.1)", language: "eng", isSelected: true),
            TrackOption(id: 1, name: "Commentary Track", language: "eng", isSelected: false)
        ]
        self.availableSubtitleTracks = [
            TrackOption(id: 0, name: "Korean (SSA/ASS Styled)", language: "kor", isSelected: true),
            TrackOption(id: 1, name: "English SDH", language: "eng", isSelected: false)
        ]

        updateState(.paused)
    }

    public func play() {
        updateState(.playing)
        startSimulationTimer()
    }

    public func pause() {
        stopSimulationTimer()
        updateState(.paused)
    }

    public func togglePlayPause() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    public func seek(to position: TimeInterval) {
        let clamped = max(0, min(position, duration))
        currentPosition = clamped
        onPositionChange?(currentPosition, duration)
    }

    public func selectAudioTrack(index: Int) {
        availableAudioTracks = availableAudioTracks.enumerated().map {
            TrackOption(id: $0.element.id, name: $0.element.name, language: $0.element.language, isSelected: $0.offset == index)
        }
    }

    public func selectSubtitleTrack(index: Int) {
        availableSubtitleTracks = availableSubtitleTracks.enumerated().map {
            TrackOption(id: $0.element.id, name: $0.element.name, language: $0.element.language, isSelected: $0.offset == index)
        }
    }

    private func startSimulationTimer() {
        stopSimulationTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self = self, self.state == .playing else { return }
                self.currentPosition += (0.25 * Double(self.playbackRate))
                if self.currentPosition >= self.duration {
                    self.currentPosition = self.duration
                    self.pause()
                }
                self.onPositionChange?(self.currentPosition, self.duration)
            }
        }
    }

    private func stopSimulationTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updateState(_ newState: PlaybackState) {
        self.state = newState
        onStateChange?(newState)
    }

    public func releaseResources() {
        stopSimulationTimer()
        currentItem = nil
        updateState(.idle)
    }

    deinit {
        releaseResources()
    }
}
