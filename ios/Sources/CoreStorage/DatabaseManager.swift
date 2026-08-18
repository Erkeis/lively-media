// [Intent] Concurrency-safe DatabaseManager managing GRDB DatabaseWriter (Queue or Pool) and migration lifecycle
import Foundation
import GRDB

public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()

    public let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public convenience init(inMemory: Bool = false, path: String? = nil) {
        do {
            if inMemory {
                let queue = try DatabaseQueue()
                try DatabaseMigrations.migrator().migrate(queue)
                self.init(dbWriter: queue)
            } else {
                let dbPath: String
                if let customPath = path {
                    dbPath = customPath
                } else {
                    let fileManager = Foundation.FileManager.default
                    let folderURL = try fileManager
                        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        .appendingPathComponent("LivelyMedia", isDirectory: true)
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    dbPath = folderURL.appendingPathComponent("library.sqlite").path
                }

                var config = Configuration()
                config.qos = .userInitiated
                config.foreignKeysEnabled = true

                let pool = try DatabasePool(path: dbPath, configuration: config)
                try DatabaseMigrations.migrator().migrate(pool)
                self.init(dbWriter: pool)
            }
        } catch {
            fatalError("Failed to initialize DatabaseManager: \(error)")
        }
    }
}
