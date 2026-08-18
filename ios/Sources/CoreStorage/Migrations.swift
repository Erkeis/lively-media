// [Intent] Database schema definitions and migrations managing tables, indexes, and full-text search
import Foundation
import GRDB

public struct DatabaseMigrations {
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Speeds up development schema iterations
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1_initial_schema") { db in
            // 1. media_items table
            try db.create(table: "media_items") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("filePath", .text).notNull().unique()
                t.column("fileName", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("duration", .double).notNull().defaults(to: 0.0)
                t.column("mediaType", .text).notNull()
                t.column("containerFormat", .text).notNull()
                t.column("codec", .text)
                t.column("artworkPath", .text)
                t.column("artist", .text)
                t.column("album", .text)
                t.column("genre", .text)
                t.column("trackNumber", .integer)
                t.column("lastPlayedAt", .datetime)
                t.column("playbackPosition", .double).notNull().defaults(to: 0.0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("waveformData", .blob)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Indexes for instant library queries
            try db.create(index: "idx_media_items_type", on: "media_items", columns: ["mediaType"])
            try db.create(index: "idx_media_items_artist", on: "media_items", columns: ["artist"])
            try db.create(index: "idx_media_items_album", on: "media_items", columns: ["album"])
            try db.create(index: "idx_media_items_favorite", on: "media_items", columns: ["isFavorite"])
            try db.create(index: "idx_media_items_last_played", on: "media_items", columns: ["lastPlayedAt"])

            // 2. playlists table
            try db.create(table: "playlists") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // 3. playlist_items table
            try db.create(table: "playlist_items") { t in
                t.column("playlistId", .text).notNull().references("playlists", onDelete: .cascade)
                t.column("mediaId", .text).notNull().references("media_items", onDelete: .cascade)
                t.column("sortOrder", .integer).notNull()
                t.primaryKey(["playlistId", "mediaId"])
            }
            try db.create(index: "idx_playlist_items_order", on: "playlist_items", columns: ["playlistId", "sortOrder"])

            // 4. bookmarks table
            try db.create(table: "bookmarks") { t in
                t.column("id", .text).primaryKey()
                t.column("mediaId", .text).notNull().references("media_items", onDelete: .cascade)
                t.column("position", .double).notNull()
                t.column("title", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_bookmarks_media_id", on: "bookmarks", columns: ["mediaId"])
        }

        return migrator
    }
}
