// [Intent] Join table entity mapping MediaItems to Playlists with sort ordering
import Foundation
import GRDB

public struct PlaylistItem: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlist_items"

    public var playlistId: String
    public var mediaId: String
    public var sortOrder: Int

    public init(
        playlistId: String,
        mediaId: String,
        sortOrder: Int
    ) {
        self.playlistId = playlistId
        self.mediaId = mediaId
        self.sortOrder = sortOrder
    }
}

extension PlaylistItem: TableRecord {
    public enum Columns {
        public static let playlistId = Column(CodingKeys.playlistId)
        public static let mediaId = Column(CodingKeys.mediaId)
        public static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
