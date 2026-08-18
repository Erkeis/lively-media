// [Intent] Chromecast local streaming bridge generating HTTP 206 stream endpoints for on-device sandbox files
import Foundation
import CoreStorage
import TransferServer

public struct CastMediaPayload: Sendable {
    public let streamURL: URL
    public let contentType: String
    public let title: String
    public let subtitle: String?
    public let duration: TimeInterval

    public init(streamURL: URL, contentType: String, title: String, subtitle: String? = nil, duration: TimeInterval) {
        self.streamURL = streamURL
        self.contentType = contentType
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
    }
}

public protocol ChromecastStreamBridgeProtocol: Sendable {
    func generateCastPayload(for item: MediaItem, serverPort: UInt16, customHost: String?) -> CastMediaPayload
}

public final class ChromecastStreamBridge: ChromecastStreamBridgeProtocol {
    public init() {}

    public func generateCastPayload(for item: MediaItem, serverPort: UInt16 = 8080, customHost: String? = nil) -> CastMediaPayload {
        let qrPayload = QRCodePayload(port: serverPort, customHost: customHost)
        let baseURLString = qrPayload.connectionURLString

        // Format stream URL: http://<local-ip>:8080/stream/<encoded-file-name>
        let encodedName = item.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.fileName
        let streamURL = URL(string: "\(baseURLString)/stream/\(encodedName)") ?? URL(fileURLWithPath: item.filePath)

        let contentType: String
        switch item.containerFormat.lowercased() {
        case "mp4", "m4v", "mov":
            contentType = "video/mp4"
        case "mkv", "webm":
            contentType = "video/webm"
        case "mp3":
            contentType = "audio/mpeg"
        case "flac":
            contentType = "audio/flac"
        case "aac", "m4a":
            contentType = "audio/aac"
        default:
            contentType = item.mediaType == .video ? "video/mp4" : "audio/mpeg"
        }

        return CastMediaPayload(
            streamURL: streamURL,
            contentType: contentType,
            title: item.title,
            subtitle: item.artist ?? item.album,
            duration: item.duration
        )
    }
}
