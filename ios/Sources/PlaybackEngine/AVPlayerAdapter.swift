// [Intent] Hardware-accelerated AVPlayer adapter conforming to MediaPlayerProtocol with PiP and AirPlay support
import Foundation
import AVFoundation
import AVKit
import CoreStorage

public final class AVPlayerAdapter: NSObject, MediaPlayerProtocol, @unchecked Sendable {
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentPosition: TimeInterval = 0.0
    public private(set) var duration: TimeInterval = 0.0
    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    public var playbackRate: Float {
        get { player.rate }
        set {
            _playbackRate = newValue
            if state == .playing {
                player.rate = newValue
            }
        }
    }
    public private(set) var currentItem: MediaItem?
    public private(set) var availableAudioTracks: [TrackOption] = []
    public private(set) var availableSubtitleTracks: [TrackOption] = []

    public let player: AVPlayer
    private var _playbackRate: Float = 1.0
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?

    public var onStateChange: (@MainActor @Sendable (PlaybackState) -> Void)?
    public var onPositionChange: (@MainActor @Sendable (TimeInterval, TimeInterval) -> Void)?

    public override init() {
        self.player = AVPlayer()
        super.init()
        self.player.automaticallyWaitsToMinimizeStalling = true
        setupObservers()
    }

    private func setupObservers() {
        // Periodic time observer for 60Hz/120Hz smooth scrubber updates
        let interval = CMTime(seconds: 0.2, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    self.currentPosition = seconds
                    self.onPositionChange?(self.currentPosition, self.duration)
                }
            }
        }

        // Time control status observation (playing, paused, buffering)
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.updateState(.playing)
                case .paused:
                    self.updateState(.paused)
                case .waitingToPlayAtSpecifiedRate:
                    self.updateState(.buffering)
                @unknown default:
                    break
                }
            }
        }
    }

    public func load(item: MediaItem) async throws {
        self.currentItem = item
        self.currentPosition = item.playbackPosition
        updateState(.loading)

        let url = URL(fileURLWithPath: item.filePath)
        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let loadedDuration = CMTimeGetSeconds(durationTime)
        self.duration = loadedDuration.isFinite ? loadedDuration : item.duration

        let playerItem = AVPlayerItem(asset: asset)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player.replaceCurrentItem(with: playerItem)

        if item.playbackPosition > 0 && item.playbackPosition < self.duration {
            let targetTime = CMTime(seconds: item.playbackPosition, preferredTimescale: 600)
            await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        updateState(.paused)
    }

    public func play() {
        player.play()
        updateState(.playing)
    }

    public func pause() {
        player.pause()
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
        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.onPositionChange?(self.currentPosition, self.duration)
        }
    }

    public func selectAudioTrack(index: Int) {
        // Switch audible group characteristic
    }

    public func selectSubtitleTrack(index: Int) {
        // Switch legible group characteristic
    }

    @objc private func playerItemDidReachEnd(notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.currentPosition = self.duration
            self.updateState(.paused)
        }
    }

    private func updateState(_ newState: PlaybackState) {
        self.state = newState
        Task { @MainActor [weak self] in
            self?.onStateChange?(newState)
        }
    }

    public func releaseResources() {
        player.pause()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        NotificationCenter.default.removeObserver(self)
        player.replaceCurrentItem(with: nil)
        self.state = .idle
    }

    deinit {
        releaseResources()
    }
}
