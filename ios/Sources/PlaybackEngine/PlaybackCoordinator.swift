// [Intent] MainActor PlaybackCoordinator managing active engine routing, queue navigation, and NowPlaying metadata synchronization
import Foundation
import SwiftUI
import Combine
import CoreStorage
import MetadataEngine

@MainActor
public final class PlaybackCoordinator: ObservableObject {
    public static let shared = PlaybackCoordinator()

    @Published public private(set) var currentItem: MediaItem?
    @Published public private(set) var state: PlaybackState = .idle
    @Published public private(set) var currentPosition: TimeInterval = 0.0
    @Published public private(set) var duration: TimeInterval = 0.0
    @Published public var volume: Float = 1.0 {
        didSet { activeEngine?.volume = volume }
    }
    @Published public var playbackRate: Float = 1.0 {
        didSet { activeEngine?.playbackRate = playbackRate }
    }
    @Published public var isMuted: Bool = false
    @Published public private(set) var queue: [MediaItem] = []
    @Published public private(set) var currentIndex: Int = 0
    @Published public var isMiniPlayerVisible: Bool = false
    @Published public var isFullscreenAudioPresented: Bool = false
    @Published public var isFullscreenVideoPresented: Bool = false

    private var avPlayerEngine: AVPlayerAdapter
    private var ksPlayerEngine: KSPlayerAdapter
    private var activeEngine: MediaPlayerProtocol?

    private let mediaRepo: MediaRepositoryProtocol
    private let nowPlayingManager: NowPlayingManagerProtocol
    private let audioSessionManager: AudioSessionManagerProtocol
    private var lastSavedPositionTime: Date = Date()

    public init(
        mediaRepo: MediaRepositoryProtocol = MediaRepository(),
        nowPlayingManager: NowPlayingManagerProtocol = NowPlayingManager.shared,
        audioSessionManager: AudioSessionManagerProtocol = AudioSessionManager.shared
    ) {
        self.mediaRepo = mediaRepo
        self.nowPlayingManager = nowPlayingManager
        self.audioSessionManager = audioSessionManager
        self.avPlayerEngine = AVPlayerAdapter()
        self.ksPlayerEngine = KSPlayerAdapter()

        setupEngineCallbacks()
        try? audioSessionManager.configurePlaybackSession()
        setupRemoteCommands()
    }

    private func setupEngineCallbacks() {
        avPlayerEngine.onStateChange = { [weak self] newState in
            self?.state = newState
            self?.syncNowPlaying()
        }
        avPlayerEngine.onPositionChange = { [weak self] pos, dur in
            self?.currentPosition = pos
            self?.duration = dur
            self?.periodicallySavePosition()
        }

        ksPlayerEngine.onStateChange = { [weak self] newState in
            self?.state = newState
            self?.syncNowPlaying()
        }
        ksPlayerEngine.onPositionChange = { [weak self] pos, dur in
            self?.currentPosition = pos
            self?.duration = dur
            self?.periodicallySavePosition()
        }
    }

    private func setupRemoteCommands() {
        nowPlayingManager.configureRemoteCommands(
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onSkipForward: { [weak self] interval in self?.seek(by: interval) },
            onSkipBackward: { [weak self] interval in self?.seek(by: -interval) },
            onSeek: { [weak self] pos in self?.seek(to: pos) }
        )
    }

    public func playQueue(_ items: [MediaItem], startIndex: Int = 0) async {
        guard !items.isEmpty, startIndex >= 0, startIndex < items.count else { return }
        self.queue = items
        self.currentIndex = startIndex
        await loadAndPlay(item: items[startIndex])
    }

    public func playItem(_ item: MediaItem) async {
        self.queue = [item]
        self.currentIndex = 0
        await loadAndPlay(item: item)
    }

    private func loadAndPlay(item: MediaItem) async {
        self.currentItem = item
        self.isMiniPlayerVisible = true

        // Select Engine: AVPlayer for native Apple containers vs KSPlayer for MKV/WebM/DTS
        let nativeFormats: Set<String> = ["mp4", "mov", "m4v", "mp3", "aac", "flac", "wav", "m4a", "m3u8"]
        let isNative = nativeFormats.contains(item.containerFormat.lowercased())

        activeEngine?.releaseResources()
        activeEngine = isNative ? avPlayerEngine : ksPlayerEngine

        do {
            try await activeEngine?.load(item: item)
            activeEngine?.volume = volume
            activeEngine?.playbackRate = playbackRate
            activeEngine?.play()
            self.state = .playing

            if item.mediaType == .video {
                self.isFullscreenVideoPresented = true
            } else {
                self.isFullscreenAudioPresented = true
            }
            syncNowPlaying()
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    public func play() {
        activeEngine?.play()
        state = .playing
        syncNowPlaying()
    }

    public func pause() {
        activeEngine?.pause()
        state = .paused
        syncNowPlaying()
    }

    public func togglePlayPause() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    public func seek(to position: TimeInterval) {
        activeEngine?.seek(to: position)
        currentPosition = position
        syncNowPlaying()
    }

    public func seek(by delta: TimeInterval) {
        seek(to: currentPosition + delta)
    }

    public func next() async {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return }
        currentIndex += 1
        await loadAndPlay(item: queue[currentIndex])
    }

    public func previous() async {
        guard !queue.isEmpty else { return }
        if currentPosition > 3.0 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            await loadAndPlay(item: queue[currentIndex])
        }
    }

    private func syncNowPlaying() {
        guard let item = currentItem else {
            nowPlayingManager.clearNowPlaying()
            return
        }
        nowPlayingManager.updateNowPlaying(
            item: item,
            currentPosition: currentPosition,
            duration: duration,
            playbackRate: state == .playing ? playbackRate : 0.0,
            artworkData: nil
        )
    }

    private func periodicallySavePosition() {
        guard let item = currentItem else { return }
        let now = Date()
        if now.timeIntervalSince(lastSavedPositionTime) >= 5.0 {
            lastSavedPositionTime = now
            Task {
                try? await mediaRepo.updatePlaybackPosition(id: item.id, position: currentPosition, lastPlayedAt: now)
            }
        }
    }
}
