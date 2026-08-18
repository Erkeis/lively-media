// [Intent] Playlist entity supporting custom ordering and metadata
import Foundation
import GRDB

public struct Playlist: Identifiable, Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlists"

    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Playlist: TableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
