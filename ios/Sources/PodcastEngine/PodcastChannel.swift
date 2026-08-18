// [Intent] Model representing a Podcast Channel and its syndicated episodes
import Foundation

public struct PodcastChannelItem: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let episodeDescription: String?
    public let audioURL: URL
    public let duration: TimeInterval
    public let pubDate: Date
    public let artworkURL: URL?

    public init(
        id: String = UUID().uuidString,
        title: String,
        episodeDescription: String? = nil,
        audioURL: URL,
        duration: TimeInterval = 0.0,
        pubDate: Date = Date(),
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioURL = audioURL
        self.duration = duration
        self.pubDate = pubDate
        self.artworkURL = artworkURL
    }
}

public struct PodcastChannel: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let channelDescription: String?
    public let author: String?
    public let feedURL: URL
    public let artworkURL: URL?
    public var episodes: [PodcastChannelItem]

    public init(
        id: String = UUID().uuidString,
        title: String,
        channelDescription: String? = nil,
        author: String? = nil,
        feedURL: URL,
        artworkURL: URL? = nil,
        episodes: [PodcastChannelItem] = []
    ) {
        self.id = id
        self.title = title
        self.channelDescription = channelDescription
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.episodes = episodes
    }
}
