// [Intent] Unit tests verifying FileTypeClassifier categorization and directory indexing flow
import XCTest
import CoreStorage
import MetadataEngine
@testable import FileManagerCore

final class FileManagerTests: XCTestCase {
    func testFileTypeClassification() {
        XCTAssertEqual(
            matchCategory(FileTypeClassifier.classify(url: URL(fileURLWithPath: "song.flac"))),
            "audio_flac"
        )
        XCTAssertEqual(
            matchCategory(FileTypeClassifier.classify(url: URL(fileURLWithPath: "movie.mkv"))),
            "video_mkv"
        )
        XCTAssertEqual(
            matchCategory(FileTypeClassifier.classify(url: URL(fileURLWithPath: "sub.ass"))),
            "subtitle_ass"
        )
        XCTAssertEqual(
            matchCategory(FileTypeClassifier.classify(url: URL(fileURLWithPath: "stream.m3u8"))),
            "stream_m3u8"
        )
        XCTAssertEqual(
            matchCategory(FileTypeClassifier.classify(url: URL(fileURLWithPath: "document.pdf"))),
            "unsupported"
        )
    }

    private func matchCategory(_ category: FileCategory) -> String {
        switch category {
        case .audio(let fmt): return "audio_\(fmt)"
        case .video(let fmt): return "video_\(fmt)"
        case .subtitle(let fmt): return "subtitle_\(fmt)"
        case .streamPlaylist(let fmt): return "stream_\(fmt)"
        case .unsupported: return "unsupported"
        }
    }

    func testDirectoryScanAndIndexMock() async throws {
        let dbManager = DatabaseManager(inMemory: true)
        let mediaRepo = MediaRepository(dbManager: dbManager)
        let fileManager = LocalFileManager(mediaRepo: mediaRepo)

        // Create temporary test folder with mock media files
        let tempDir = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Foundation.FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? Foundation.FileManager.default.removeItem(at: tempDir) }

        let sample1 = tempDir.appendingPathComponent("track1.mp3")
        let sample2 = tempDir.appendingPathComponent("video1.mp4")
        let sample3 = tempDir.appendingPathComponent("notes.txt")

        try "fake audio data".write(to: sample1, atomically: true, encoding: .utf8)
        try "fake video data".write(to: sample2, atomically: true, encoding: .utf8)
        try "text data".write(to: sample3, atomically: true, encoding: .utf8)

        let indexed = try await fileManager.scanAndIndexDirectory(at: tempDir)
        XCTAssertEqual(indexed.count, 2) // notes.txt is ignored

        let allAudio = try await mediaRepo.fetchAll(mediaType: .audio)
        let allVideo = try await mediaRepo.fetchAll(mediaType: .video)
        XCTAssertEqual(allAudio.count, 1)
        XCTAssertEqual(allVideo.count, 1)
    }
}
