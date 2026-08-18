// [Intent] High-performance file scanner and reactive directory observer for iOS Files App auto-indexing
import Foundation
import CoreStorage
import MetadataEngine

public protocol LocalFileManagerProtocol: Sendable {
    func scanAndIndexDirectory(at url: URL) async throws -> [MediaItem]
    func importFile(from sourceURL: URL, into destinationDirectory: URL) async throws -> MediaItem
    func startDirectoryWatcher(at url: URL, onChange: @escaping @Sendable () -> Void) -> (any Sendable)?
}

public final class LocalFileManager: LocalFileManagerProtocol, @unchecked Sendable {
    private let mediaRepo: MediaRepositoryProtocol
    private let metadataParser: MetadataParserProtocol
    private var activeWatchers: [String: DispatchSourceFileSystemObject] = [:]

    public init(
        mediaRepo: MediaRepositoryProtocol,
        metadataParser: MetadataParserProtocol = MetadataParser()
    ) {
        self.mediaRepo = mediaRepo
        self.metadataParser = metadataParser
    }

    public func scanAndIndexDirectory(at url: URL) async throws -> [MediaItem] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var scannedItems: [MediaItem] = []
        for case let fileURL as URL in enumerator {
            let category = FileTypeClassifier.classify(url: fileURL)
            switch category {
            case .audio, .video:
                do {
                    let item = try await metadataParser.createMediaItem(from: fileURL)
                    try await mediaRepo.insert(item)
                    scannedItems.append(item)
                } catch {
                    // Continue indexing remaining items upon single file failure
                    continue
                }
            default:
                continue
            }
        }
        return scannedItems
    }

    public func importFile(from sourceURL: URL, into destinationDirectory: URL) async throws -> MediaItem {
        let fileManager = FileManager.default
        let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let item = try await metadataParser.createMediaItem(from: destinationURL)
        try await mediaRepo.insert(item)
        return item
    }

    public func startDirectoryWatcher(at url: URL, onChange: @escaping @Sendable () -> Void) -> (any Sendable)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler {
            onChange()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        activeWatchers[url.path] = source
        return source
    }
}
