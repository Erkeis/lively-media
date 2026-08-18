// [Intent] Comprehensive unit tests verifying CoreStorage GRDB migrations, CRUD, search, and playlist operations
import XCTest
import GRDB
@testable import CoreStorage

final class DatabaseTests: XCTestCase {
    var dbManager: DatabaseManager!
    var mediaRepo: MediaRepository!
    var playlistRepo: PlaylistRepository!

    override func setUp() async throws {
        // Initialize in-memory database for isolated, high-speed test execution
        dbManager = DatabaseManager(inMemory: true)
        mediaRepo = MediaRepository(dbManager: dbManager)
        playlistRepo = PlaylistRepository(dbManager: dbManager)
    }

    func testMediaItemInsertAndFetch() async throws {
        let item = MediaItem(
            title: "Test Track",
            filePath: "/sandbox/music/track1.flac",
            fileName: "track1.flac",
            fileSize: 45_000_000,
            duration: 240.5,
            mediaType: .audio,
            containerFormat: "flac",
            artist: "Studio Artist",
            album: "Master Album"
        )

        try await mediaRepo.insert(item)

        let fetched = try await mediaRepo.fetch(id: item.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Track")
        XCTAssertEqual(fetched?.containerFormat, "flac")
        XCTAssertEqual(fetched?.artist, "Studio Artist")
        XCTAssertEqual(fetched?.fileSize, 45_000_000)
    }

    func testMediaSearchAndFilter() async throws {
        let audio1 = MediaItem(
            title: "Midnight Jazz",
            filePath: "/sandbox/music/jazz.mp3",
            fileName: "jazz.mp3",
            fileSize: 10_000_000,
            mediaType: .audio,
            containerFormat: "mp3",
            artist: "Miles Duo"
        )
        let audio2 = MediaItem(
            title: "Morning Classical",
            filePath: "/sandbox/music/classic.flac",
            fileName: "classic.flac",
            fileSize: 30_000_000,
            mediaType: .audio,
            containerFormat: "flac",
            artist: "Chopin"
        )
        let video1 = MediaItem(
            title: "Concert Live 4K",
            filePath: "/sandbox/video/live.mp4",
            fileName: "live.mp4",
            fileSize: 1_200_000_000,
            mediaType: .video,
            containerFormat: "mp4"
        )

        try await mediaRepo.batchInsert([audio1, audio2, video1])

        let allAudio = try await mediaRepo.fetchAll(mediaType: .audio)
        XCTAssertEqual(allAudio.count, 2)

        let searchResults = try await mediaRepo.search(query: "Jazz")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.title, "Midnight Jazz")
    }

    func testPlaybackPositionUpdateAndFavorites() async throws {
        let item = MediaItem(
            title: "Long Podcast Episode",
            filePath: "/sandbox/audio/podcast.mp3",
            fileName: "podcast.mp3",
            fileSize: 50_000_000,
            mediaType: .audio,
            containerFormat: "mp3"
        )
        try await mediaRepo.insert(item)

        try await mediaRepo.updatePlaybackPosition(id: item.id, position: 1540.2)
        let updated = try await mediaRepo.fetch(id: item.id)
        XCTAssertEqual(updated?.playbackPosition, 1540.2)
        XCTAssertNotNil(updated?.lastPlayedAt)

        let isFav = try await mediaRepo.toggleFavorite(id: item.id)
        XCTAssertTrue(isFav)
        let afterFav = try await mediaRepo.fetch(id: item.id)
        XCTAssertTrue(afterFav?.isFavorite == true)
    }

    func testPlaylistCreationAndItemReordering() async throws {
        let item1 = MediaItem(title: "Track 1", filePath: "/p/1.mp3", fileName: "1.mp3", fileSize: 100, mediaType: .audio, containerFormat: "mp3")
        let item2 = MediaItem(title: "Track 2", filePath: "/p/2.mp3", fileName: "2.mp3", fileSize: 100, mediaType: .audio, containerFormat: "mp3")
        let item3 = MediaItem(title: "Track 3", filePath: "/p/3.mp3", fileName: "3.mp3", fileSize: 100, mediaType: .audio, containerFormat: "mp3")

        try await mediaRepo.batchInsert([item1, item2, item3])

        let playlist = try await playlistRepo.createPlaylist(name: "Roadtrip Chill")
        XCTAssertEqual(playlist.name, "Roadtrip Chill")

        try await playlistRepo.addMediaToPlaylist(playlistId: playlist.id, mediaId: item1.id)
        try await playlistRepo.addMediaToPlaylist(playlistId: playlist.id, mediaId: item2.id)
        try await playlistRepo.addMediaToPlaylist(playlistId: playlist.id, mediaId: item3.id)

        let itemsInPlaylist = try await playlistRepo.fetchMediaItems(in: playlist.id)
        XCTAssertEqual(itemsInPlaylist.count, 3)
        XCTAssertEqual(itemsInPlaylist[0].id, item1.id)
        XCTAssertEqual(itemsInPlaylist[1].id, item2.id)
        XCTAssertEqual(itemsInPlaylist[2].id, item3.id)

        // Test Reordering: Reverse order
        try await playlistRepo.reorderPlaylist(playlistId: playlist.id, orderedMediaIds: [item3.id, item2.id, item1.id])
        let reordered = try await playlistRepo.fetchMediaItems(in: playlist.id)
        XCTAssertEqual(reordered[0].id, item3.id)
        XCTAssertEqual(reordered[1].id, item2.id)
        XCTAssertEqual(reordered[2].id, item1.id)
    }
}
