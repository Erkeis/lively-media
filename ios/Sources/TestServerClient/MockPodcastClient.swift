// [Intent] Mock podcast & RSS feed client for podcast streaming verification on Linux test server
import Foundation

public struct PodcastEpisode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let audioURL: URL
    public let duration: TimeInterval
    public let publishDate: Date

    public init(id: String = UUID().uuidString, title: String, audioURL: URL, duration: TimeInterval, publishDate: Date = Date()) {
        self.id = id
        self.title = title
        self.audioURL = audioURL
        self.duration = duration
        self.publishDate = publishDate
    }
}

public protocol MockPodcastClientProtocol: Sendable {
    func fetchFeed(feedURL: URL) async throws -> [PodcastEpisode]
}

public final class MockPodcastClient: MockPodcastClientProtocol {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchFeed(feedURL: URL) async throws -> [PodcastEpisode] {
        return [
            PodcastEpisode(
                title: "Episode 1: Studio Mastering in Obsidian Dark",
                audioURL: feedURL.deletingLastPathComponent().appendingPathComponent("media/sample_audio.mp3"),
                duration: 3600.0
            ),
            PodcastEpisode(
                title: "Episode 2: High-Resolution FLAC Architecture",
                audioURL: feedURL.deletingLastPathComponent().appendingPathComponent("media/sample_hires.flac"),
                duration: 2400.0
            )
        ]
    }
}
