// [Intent] Model representing a background media download task with state and progress tracking
import Foundation

public enum DownloadState: Sendable, Equatable {
    case queued
    case downloading(progress: Double, speedBytesPerSec: Double)
    case paused(resumeData: Data?)
    case completed(fileURL: URL)
    case failed(String)
}

public struct DownloadTaskItem: Identifiable, Sendable {
    public let id: String
    public let remoteURL: URL
    public let destinationURL: URL
    public let title: String
    public var state: DownloadState
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        remoteURL: URL,
        destinationURL: URL,
        title: String,
        state: DownloadState = .queued,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.destinationURL = destinationURL
        self.title = title
        self.state = state
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.createdAt = createdAt
    }
}
