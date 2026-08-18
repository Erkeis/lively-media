// [Intent] Async repository handling CRUD, filtered queries, search, and batch operations for MediaItem
import Foundation
import GRDB

public protocol MediaRepositoryProtocol: Sendable {
    func insert(_ item: MediaItem) async throws
    func batchInsert(_ items: [MediaItem]) async throws
    func update(_ item: MediaItem) async throws
    func delete(id: String) async throws
    func fetch(id: String) async throws -> MediaItem?
    func fetchAll(mediaType: MediaType?) async throws -> [MediaItem]
    func search(query: String) async throws -> [MediaItem]
    func updatePlaybackPosition(id: String, position: Double, lastPlayedAt: Date) async throws
    func toggleFavorite(id: String) async throws -> Bool
}

public final class MediaRepository: MediaRepositoryProtocol {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    public func insert(_ item: MediaItem) async throws {
        try await dbManager.dbWriter.write { db in
            try item.save(db)
        }
    }

    public func batchInsert(_ items: [MediaItem]) async throws {
        try await dbManager.dbWriter.write { db in
            for item in items {
                try item.save(db)
            }
        }
    }

    public func update(_ item: MediaItem) async throws {
        try await dbManager.dbWriter.write { db in
            try item.update(db)
        }
    }

    public func delete(id: String) async throws {
        try await dbManager.dbWriter.write { db in
            _ = try MediaItem.deleteOne(db, id: id)
        }
    }

    public func fetch(id: String) async throws -> MediaItem? {
        try await dbManager.dbWriter.read { db in
            try MediaItem.fetchOne(db, id: id)
        }
    }

    public func fetchAll(mediaType: MediaType? = nil) async throws -> [MediaItem] {
        try await dbManager.dbWriter.read { db in
            var request = MediaItem.all().order(MediaItem.Columns.title.asc)
            if let type = mediaType {
                request = request.filter(MediaItem.Columns.mediaType == type.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    public func search(query: String) async throws -> [MediaItem] {
        let pattern = "%\(query)%"
        return try await dbManager.dbWriter.read { db in
            try MediaItem
                .filter(
                    MediaItem.Columns.title.like(pattern) ||
                    MediaItem.Columns.artist.like(pattern) ||
                    MediaItem.Columns.album.like(pattern) ||
                    MediaItem.Columns.fileName.like(pattern)
                )
                .order(MediaItem.Columns.title.asc)
                .fetchAll(db)
        }
    }

    public func updatePlaybackPosition(id: String, position: Double, lastPlayedAt: Date = Date()) async throws {
        try await dbManager.dbWriter.write { db in
            if var item = try MediaItem.fetchOne(db, id: id) {
                item.playbackPosition = position
                item.lastPlayedAt = lastPlayedAt
                item.updatedAt = Date()
                try item.update(db)
            }
        }
    }

    public func toggleFavorite(id: String) async throws -> Bool {
        try await dbManager.dbWriter.write { db in
            guard var item = try MediaItem.fetchOne(db, id: id) else {
                return false
            }
            item.isFavorite.toggle()
            item.updatedAt = Date()
            try item.update(db)
            return item.isFavorite
        }
    }
}
