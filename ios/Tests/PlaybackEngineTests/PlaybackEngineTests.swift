// [Intent] Unit tests verifying PlaybackEngine state transitions, queue navigation, and engine switching logic
import XCTest
import CoreStorage
@testable import PlaybackEngine

final class PlaybackEngineTests: XCTestCase {
    @MainActor
    func testKSPlayerAdapterPlaybackStateFlow() async throws {
        let adapter = KSPlayerAdapter()
        let item = MediaItem(
            title: "Anime Episode 1",
            filePath: "/sandbox/mkv/anime.mkv",
            fileName: "anime.mkv",
            fileSize: 500_000_000,
            duration: 1420.0,
            mediaType: .video,
            containerFormat: "mkv"
        )

        try await adapter.load(item: item)
        XCTAssertEqual(adapter.state, .paused)
        XCTAssertEqual(adapter.duration, 1420.0)

        adapter.play()
        XCTAssertEqual(adapter.state, .playing)

        adapter.pause()
        XCTAssertEqual(adapter.state, .paused)

        adapter.seek(to: 500.0)
        XCTAssertEqual(adapter.currentPosition, 500.0)

        XCTAssertEqual(adapter.availableSubtitleTracks.count, 2)
        adapter.selectSubtitleTrack(index: 1)
        XCTAssertTrue(adapter.availableSubtitleTracks[1].isSelected)
    }

    @MainActor
    func testPlaybackCoordinatorQueueNavigation() async throws {
        let dbManager = DatabaseManager(inMemory: true)
        let mediaRepo = MediaRepository(dbManager: dbManager)
        let coordinator = PlaybackCoordinator(mediaRepo: mediaRepo)

        let track1 = MediaItem(title: "Track 1", filePath: "/p/1.mp3", fileName: "1.mp3", fileSize: 100, duration: 180, mediaType: .audio, containerFormat: "mp3")
        let track2 = MediaItem(title: "Track 2", filePath: "/p/2.mp3", fileName: "2.mp3", fileSize: 100, duration: 200, mediaType: .audio, containerFormat: "mp3")

        await coordinator.playQueue([track1, track2], startIndex: 0)

        XCTAssertEqual(coordinator.currentItem?.id, track1.id)
        XCTAssertEqual(coordinator.currentIndex, 0)
        XCTAssertTrue(coordinator.isMiniPlayerVisible)

        await coordinator.next()
        XCTAssertEqual(coordinator.currentItem?.id, track2.id)
        XCTAssertEqual(coordinator.currentIndex, 1)

        await coordinator.previous()
        XCTAssertEqual(coordinator.currentItem?.id, track1.id)
        XCTAssertEqual(coordinator.currentIndex, 0)
    }
}
