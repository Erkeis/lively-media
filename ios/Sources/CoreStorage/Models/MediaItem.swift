// [Intent] High-performance, concurrency-safe MediaItem model conforming to GRDB records and Codable
import Foundation
import GRDB

public enum MediaType: String, Codable, Sendable, DatabaseValueConvertible {
    case audio
    case video
}

public struct MediaItem: Identifiable, Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "media_items"

    public var id: String
    public var title: String
    public var filePath: String
    public var fileName: String
    public var fileSize: Int64
    public var duration: Double
    public var mediaType: MediaType
    public var containerFormat: String
    public var codec: String?
    public var artworkPath: String?
    public var artist: String?
    public var album: String?
    public var genre: String?
    public var trackNumber: Int?
    public var lastPlayedAt: Date?
    public var playbackPosition: Double
    public var isFavorite: Bool
    public var waveformData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        filePath: String,
        fileName: String,
        fileSize: Int64,
        duration: Double = 0.0,
        mediaType: MediaType,
        containerFormat: String,
        codec: String? = nil,
        artworkPath: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        trackNumber: Int? = nil,
        lastPlayedAt: Date? = nil,
        playbackPosition: Double = 0.0,
        isFavorite: Bool = false,
        waveformData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.mediaType = mediaType
        self.containerFormat = containerFormat.lowercased()
        self.codec = codec
        self.artworkPath = artworkPath
        self.artist = artist
        self.album = album
        self.genre = genre
        self.trackNumber = trackNumber
        self.lastPlayedAt = lastPlayedAt
        self.playbackPosition = playbackPosition
        self.isFavorite = isFavorite
        self.waveformData = waveformData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension MediaItem: TableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let title = Column(CodingKeys.title)
        public static let filePath = Column(CodingKeys.filePath)
        public static let fileName = Column(CodingKeys.fileName)
        public static let fileSize = Column(CodingKeys.fileSize)
        public static let duration = Column(CodingKeys.duration)
        public static let mediaType = Column(CodingKeys.mediaType)
        public static let containerFormat = Column(CodingKeys.containerFormat)
        public static let codec = Column(CodingKeys.codec)
        public static let artworkPath = Column(CodingKeys.artworkPath)
        public static let artist = Column(CodingKeys.artist)
        public static let album = Column(CodingKeys.album)
        public static let genre = Column(CodingKeys.genre)
        public static let trackNumber = Column(CodingKeys.trackNumber)
        public static let lastPlayedAt = Column(CodingKeys.lastPlayedAt)
        public static let playbackPosition = Column(CodingKeys.playbackPosition)
        public static let isFavorite = Column(CodingKeys.isFavorite)
        public static let waveformData = Column(CodingKeys.waveformData)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
