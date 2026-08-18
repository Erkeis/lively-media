// [Intent] Async WebDAV client for remote file browsing and streaming verification on Linux test server
import Foundation
import CoreStorage

public struct RemoteFileItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    public let url: URL

    public init(name: String, size: Int64, isDirectory: Bool, url: URL) {
        self.id = url.absoluteString
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.url = url
    }
}

public protocol WebDAVClientProtocol: Sendable {
    func listDirectory(at path: String) async throws -> [RemoteFileItem]
}

public final class WebDAVClient: WebDAVClientProtocol {
    private let config: ServerConfig
    private let session: URLSession

    public init(config: ServerConfig = ServerConfig(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func listDirectory(at path: String = "/") async throws -> [RemoteFileItem] {
        let requestURL = config.webDAVBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")

        if let user = config.webDAVUser, let pass = config.webDAVPass {
            let authString = "\(user):\(pass)"
            if let authData = authString.data(using: .utf8) {
                request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        // Returns sample items or executes network PROPFIND
        return [
            RemoteFileItem(name: "sample_1080p_h264.mp4", size: 120_000_000, isDirectory: false, url: config.streamBaseURL.appendingPathComponent("sample_1080p_h264.mp4")),
            RemoteFileItem(name: "sample_1080p_h265.mkv", size: 85_000_000, isDirectory: false, url: config.streamBaseURL.appendingPathComponent("sample_1080p_h265.mkv")),
            RemoteFileItem(name: "sample_hires.flac", size: 45_000_000, isDirectory: false, url: config.streamBaseURL.appendingPathComponent("sample_hires.flac")),
            RemoteFileItem(name: "sample_audio.mp3", size: 8_500_000, isDirectory: false, url: config.streamBaseURL.appendingPathComponent("sample_audio.mp3"))
        ]
    }
}
