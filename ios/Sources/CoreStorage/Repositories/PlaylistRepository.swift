// [Intent] Async repository handling playlist lifecycle, ordering, and relational media queries
import Foundation
import GRDB

public protocol PlaylistRepositoryProtocol: Sendable {
    func createPlaylist(name: String) async throws -> Playlist
    func deletePlaylist(id: String) async throws
    func fetchAllPlaylists() async throws -> [Playlist]
    func addMediaToPlaylist(playlistId: String, mediaId: String) async throws
    func removeMediaFromPlaylist(playlistId: String, mediaId: String) async throws
    func fetchMediaItems(in playlistId: String) async throws -> [MediaItem]
    func reorderPlaylist(playlistId: String, orderedMediaIds: [String]) async throws
}

public final class PlaylistRepository: PlaylistRepositoryProtocol {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    public func createPlaylist(name: String) async throws -> Playlist {
        let playlist = Playlist(name: name)
        try await dbManager.dbWriter.write { db in
            try playlist.insert(db)
        }
        return playlist
    }

    public func deletePlaylist(id: String) async throws {
        try await dbManager.dbWriter.write { db in
            _ = try Playlist.deleteOne(db, id: id)
        }
    }

    public func fetchAllPlaylists() async throws -> [Playlist] {
        try await dbManager.dbWriter.read { db in
            try Playlist.all().order(Playlist.Columns.name.asc).fetchAll(db)
        }
    }

    public func addMediaToPlaylist(playlistId: String, mediaId: String) async throws {
        try await dbManager.dbWriter.write { db in
            let maxOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sortOrder), 0) FROM playlist_items WHERE playlistId = ?",
                arguments: [playlistId]
            ) ?? 0

            let item = PlaylistItem(playlistId: playlistId, mediaId: mediaId, sortOrder: maxOrder + 1)
            try item.save(db)
        }
    }

    public func removeMediaFromPlaylist(playlistId: String, mediaId: String) async throws {
        try await dbManager.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM playlist_items WHERE playlistId = ? AND mediaId = ?",
                arguments: [playlistId, mediaId]
            )
        }
    }

    public func fetchMediaItems(in playlistId: String) async throws -> [MediaItem] {
        try await dbManager.dbWriter.read { db in
            let sql = """
            SELECT m.*
            FROM media_items m
            INNER JOIN playlist_items p ON m.id = p.mediaId
            WHERE p.playlistId = ?
            ORDER BY p.sortOrder ASC
            """
            return try MediaItem.fetchAll(db, sql: sql, arguments: [playlistId])
        }
    }

    public func reorderPlaylist(playlistId: String, orderedMediaIds: [String]) async throws {
        try await dbManager.dbWriter.write { db in
            for (index, mediaId) in orderedMediaIds.enumerated() {
                try db.execute(
                    sql: "UPDATE playlist_items SET sortOrder = ? WHERE playlistId = ? AND mediaId = ?",
                    arguments: [index, playlistId, mediaId]
                )
            }
        }
    }
}
