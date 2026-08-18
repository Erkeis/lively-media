// [Intent] Background URLSession manager handling concurrent downloads, app suspension recovery, and auto-indexing into SQLite
import Foundation
import CoreStorage
import MetadataEngine

public protocol BackgroundDownloadManagerProtocol: AnyObject, Sendable {
    func startDownload(remoteURL: URL, title: String) -> DownloadTaskItem
    func pauseDownload(taskId: String)
    func resumeDownload(taskId: String)
    func cancelDownload(taskId: String)
}

public final class BackgroundDownloadManager: NSObject, BackgroundDownloadManagerProtocol, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = BackgroundDownloadManager()

    public private(set) var activeTasks: [String: DownloadTaskItem] = [:]
    private var downloadSessions: [String: URLSessionDownloadTask] = [:]
    private var session: URLSession!

    private let mediaRepo: MediaRepositoryProtocol
    private let metadataParser: MetadataParserProtocol
    private let destinationDirectory: URL

    public init(
        mediaRepo: MediaRepositoryProtocol = MediaRepository(),
        metadataParser: MetadataParserProtocol = MetadataParser(),
        destinationDirectory: URL? = nil
    ) {
        self.mediaRepo = mediaRepo
        self.metadataParser = metadataParser
        if let dir = destinationDirectory {
            self.destinationDirectory = dir
        } else {
            let docs = Foundation.FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.destinationDirectory = docs.appendingPathComponent("Downloads", isDirectory: true)
            try? Foundation.FileManager.default.createDirectory(at: self.destinationDirectory, withIntermediateDirectories: true)
        }
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: "com.livelymedia.downloader.\(UUID().uuidString)")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func startDownload(remoteURL: URL, title: String) -> DownloadTaskItem {
        let filename = remoteURL.lastPathComponent.isEmpty ? "media_\(UUID().uuidString).mp4" : remoteURL.lastPathComponent
        let destURL = destinationDirectory.appendingPathComponent(filename)

        var item = DownloadTaskItem(remoteURL: remoteURL, destinationURL: destURL, title: title)
        item.state = .downloading(progress: 0.0, speedBytesPerSec: 0.0)
        activeTasks[item.id] = item

        let downloadTask = session.downloadTask(with: remoteURL)
        downloadTask.taskDescription = item.id
        downloadSessions[item.id] = downloadTask
        downloadTask.resume()

        return item
    }

    public func pauseDownload(taskId: String) {
        guard let task = downloadSessions[taskId] else { return }
        task.cancel(byProducingResumeData: { [weak self] resumeData in
            self?.activeTasks[taskId]?.state = .paused(resumeData: resumeData)
        })
    }

    public func resumeDownload(taskId: String) {
        guard let item = activeTasks[taskId],
              case .paused(let resumeData) = item.state,
              let data = resumeData else { return }

        let resumedTask = session.downloadTask(withResumeData: data)
        resumedTask.taskDescription = taskId
        downloadSessions[taskId] = resumedTask
        activeTasks[taskId]?.state = .downloading(progress: 0.0, speedBytesPerSec: 0.0)
        resumedTask.resume()
    }

    public func cancelDownload(taskId: String) {
        downloadSessions[taskId]?.cancel()
        downloadSessions.removeValue(forKey: taskId)
        activeTasks.removeValue(forKey: taskId)
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = downloadTask.taskDescription,
              let item = activeTasks[taskId] else { return }

        let fileManager = Foundation.FileManager.default
        do {
            if fileManager.fileExists(atPath: item.destinationURL.path) {
                try fileManager.removeItem(at: item.destinationURL)
            }
            try fileManager.moveItem(at: location, to: item.destinationURL)
            activeTasks[taskId]?.state = .completed(fileURL: item.destinationURL)

            // Auto-index into SQLite database
            Task {
                if let mediaItem = try? await self.metadataParser.createMediaItem(from: item.destinationURL) {
                    try? await self.mediaRepo.insert(mediaItem)
                }
            }
        } catch {
            activeTasks[taskId]?.state = .failed(error.localizedDescription)
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskId = downloadTask.taskDescription else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        activeTasks[taskId]?.downloadedBytes = totalBytesWritten
        activeTasks[taskId]?.totalBytes = totalBytesExpectedToWrite
        activeTasks[taskId]?.state = .downloading(progress: progress, speedBytesPerSec: Double(bytesWritten))
    }
}
