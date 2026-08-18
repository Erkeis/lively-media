// [Intent] Structured metadata extracted from audio containers (MP3, AAC, FLAC, ALAC, WAV)
import Foundation

public struct AudioMetadata: Sendable, Codable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var genre: String?
    public var trackNumber: Int?
    public var duration: Double
    public var sampleRate: Double?
    public var bitDepth: Int?
    public var channelCount: Int?
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        trackNumber: Int? = nil,
        duration: Double = 0.0,
        sampleRate: Double? = nil,
        bitDepth: Int? = nil,
        channelCount: Int? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.trackNumber = trackNumber
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.artworkData = artworkData
    }
}
