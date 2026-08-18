// [Intent] Unit tests verifying MetadataEngine data parsing, serialization, and fallback behavior
import XCTest
import CoreStorage
@testable import MetadataEngine

final class MetadataTests: XCTestCase {
    var parser: MetadataParser!
    var waveformGen: WaveformGenerator!

    override func setUp() {
        parser = MetadataParser()
        waveformGen = WaveformGenerator()
    }

    func testWaveformSerializationAndDeserialization() {
        let originalSamples: [Float] = [0.1, 0.45, 0.89, 1.0, 0.72, 0.33, 0.05]
        let serializedData = waveformGen.serializeWaveform(originalSamples)
        XCTAssertFalse(serializedData.isEmpty)

        let deserialized = waveformGen.deserializeWaveform(serializedData)
        XCTAssertEqual(deserialized.count, originalSamples.count)
        for (idx, val) in deserialized.enumerated() {
            XCTAssertEqual(val, originalSamples[idx], accuracy: 0.0001)
        }
    }

    func testCreateMediaItemFromSyntheticAudioURL() async throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/sample_song.mp3")
        let item = try await parser.createMediaItem(from: fakeURL)

        XCTAssertEqual(item.fileName, "sample_song.mp3")
        XCTAssertEqual(item.containerFormat, "mp3")
        XCTAssertEqual(item.mediaType, .audio)
        XCTAssertEqual(item.title, "sample_song")
    }

    func testCreateMediaItemFromSyntheticVideoURL() async throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/sample_movie.mkv")
        let item = try await parser.createMediaItem(from: fakeURL)

        XCTAssertEqual(item.fileName, "sample_movie.mkv")
        XCTAssertEqual(item.containerFormat, "mkv")
        XCTAssertEqual(item.mediaType, .video)
        XCTAssertEqual(item.title, "sample_movie")
    }
}
