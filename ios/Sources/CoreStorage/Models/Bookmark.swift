// [Intent] Playback timestamp bookmark for chapters and user marked points
import Foundation
import GRDB

public struct Bookmark: Identifiable, Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bookmarks"

    public var id: String
    public var mediaId: String
    public var position: Double
    public var title: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        mediaId: String,
        position: Double,
        title: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mediaId = mediaId
        self.position = position
        self.title = title
        self.createdAt = createdAt
    }
}

extension Bookmark: TableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let mediaId = Column(CodingKeys.mediaId)
        public static let position = Column(CodingKeys.position)
        public static let title = Column(CodingKeys.title)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
