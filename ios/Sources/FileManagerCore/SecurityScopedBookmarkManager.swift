// [Intent] Manages Security-Scoped Bookmarks for external USB drives, SSDs, and external iCloud Drive folders
import Foundation

public protocol SecurityScopedBookmarkManagerProtocol: Sendable {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(url: URL) -> Bool
    func stopAccessing(url: URL)
}

public final class SecurityScopedBookmarkManager: SecurityScopedBookmarkManagerProtocol {
    public init() {}

    public func createBookmark(for url: URL) throws -> Data {
        #if os(iOS) || os(macOS)
        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return url.absoluteString.data(using: .utf8) ?? Data()
        #endif
    }

    public func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        #if os(iOS) || os(macOS)
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (resolvedURL, isStale)
        #else
        let str = String(data: data, encoding: .utf8) ?? ""
        return (URL(fileURLWithPath: str), false)
        #endif
    }

    public func startAccessing(url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
