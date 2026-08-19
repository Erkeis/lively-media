// [Intent] Pure-Swift Cast V2 wire framing, protocol namespaces, command serialization, and media status parsers
import Foundation

// MARK: - Cast V2 Namespaces

public enum CastV2Namespace {
    public static let connection = "urn:x-cast:com.google.cast.tp.connection"
    public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    public static let receiver = "urn:x-cast:com.google.cast.receiver"
    public static let media = "urn:x-cast:com.google.cast.media"
}

public typealias CastNamespace = CastV2Namespace

// MARK: - Cast App IDs & Protocol Constants

public enum CastV2AppId {
    /// Google Default Media Receiver app identifier for standard audio/video playback
    public static let defaultMediaReceiver = "CC1AD845"
}

public enum CastV2Endpoint {
    public static let defaultSenderId = "sender-0"
    public static let defaultReceiverId = "receiver-0"
    public static let defaultPort: UInt16 = 8009
}

// MARK: - Wire Framing (4-Byte Big-Endian Length Prefix)

public enum CastV2Framer {
    /// Encodes a payload Data with a 4-byte big-endian length prefix
    // [Intent] Big-endian UInt32 length prefix ensures alignment-independent transmission over TLS sockets
    public static func encodeFramedMessage(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(data)
        return framed
    }

    /// Encodes a UTF-8 string with a 4-byte big-endian length prefix
    public static func encodeFramedString(_ text: String) -> Data {
        let payload = Data(text.utf8)
        return encodeFramedMessage(payload)
    }

    /// Encodes an Encodable struct to JSON data with a 4-byte big-endian length prefix
    public static func encodeFramedJSON<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        let payload = try encoder.encode(value)
        return encodeFramedMessage(payload)
    }

    /// Decodes the first complete framed message from a streaming byte buffer, removing it from the buffer
    // [Intent] Buffer slicing allows handling TCP fragmentation or multiple merged packets in a single read
    public static func decodeFramedMessage(from buffer: inout Data) -> Data? {
        guard buffer.count >= 4 else { return nil }

        var rawLength: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &rawLength) { lengthPtr in
            buffer.copyBytes(to: lengthPtr, count: 4)
        }
        let payloadLength = Int(UInt32(bigEndian: rawLength))
        let totalLength = 4 + payloadLength

        guard buffer.count >= totalLength else { return nil }

        let payload = buffer.subdata(in: 4..<totalLength)
        buffer.removeSubrange(0..<totalLength)
        return payload
    }
}

// MARK: - Connection Protocol Models

public struct CastConnectCommand: Codable, Sendable, Equatable {
    public let type: String
    public let package: String?

    public init(package: String? = nil) {
        self.type = "CONNECT"
        self.package = package
    }
}

public struct CastCloseCommand: Codable, Sendable, Equatable {
    public let type: String

    public init() {
        self.type = "CLOSE"
    }
}

// MARK: - Heartbeat Protocol Models

public struct CastPingCommand: Codable, Sendable, Equatable {
    public let type: String

    public init() {
        self.type = "PING"
    }
}

public struct CastPongCommand: Codable, Sendable, Equatable {
    public let type: String

    public init() {
        self.type = "PONG"
    }
}

// MARK: - Receiver Control Protocol Models

public struct CastLaunchCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let appId: String

    public init(requestId: Int = 1, appId: String = CastV2AppId.defaultMediaReceiver) {
        self.type = "LAUNCH"
        self.requestId = requestId
        self.appId = appId
    }
}

public struct CastReceiverGetStatusCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int

    public init(requestId: Int = 1) {
        self.type = "GET_STATUS"
        self.requestId = requestId
    }
}

public struct CastReceiverStopCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let sessionId: String

    public init(requestId: Int = 1, sessionId: String) {
        self.type = "STOP"
        self.requestId = requestId
        self.sessionId = sessionId
    }
}

// MARK: - Media Payload Models

public struct CastImage: Codable, Sendable, Equatable {
    public let url: String
    public let height: Int?
    public let width: Int?

    public init(url: String, height: Int? = nil, width: Int? = nil) {
        self.url = url
        self.height = height
        self.width = width
    }
}

public struct CastMediaMetadata: Codable, Sendable, Equatable {
    public let metadataType: Int
    public let title: String
    public let subtitle: String?
    public let artist: String?
    public let albumName: String?
    public let images: [CastImage]?

    public init(
        metadataType: Int = 0,
        title: String,
        subtitle: String? = nil,
        artist: String? = nil,
        albumName: String? = nil,
        images: [CastImage]? = nil
    ) {
        self.metadataType = metadataType
        self.title = title
        self.subtitle = subtitle
        self.artist = artist
        self.albumName = albumName
        self.images = images
    }
}

public struct CastMediaInfo: Codable, Sendable, Equatable {
    public let contentId: String
    public let streamType: String
    public let contentType: String
    public let metadata: CastMediaMetadata?
    public let duration: Double?

    public init(
        contentId: String,
        streamType: String = "BUFFERED",
        contentType: String,
        metadata: CastMediaMetadata? = nil,
        duration: Double? = nil
    ) {
        self.contentId = contentId
        self.streamType = streamType
        self.contentType = contentType
        self.metadata = metadata
        self.duration = duration
    }
}

public extension CastMediaInfo {
    var title: String? {
        metadata?.title
    }

    var subtitle: String? {
        metadata?.subtitle
    }
}

public struct CastLoadCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let sessionId: String?
    public let media: CastMediaInfo
    public let autoplay: Bool
    public let currentTime: Double

    public init(
        requestId: Int = 1,
        sessionId: String? = nil,
        media: CastMediaInfo,
        autoplay: Bool = true,
        currentTime: Double = 0.0
    ) {
        self.type = "LOAD"
        self.requestId = requestId
        self.sessionId = sessionId
        self.media = media
        self.autoplay = autoplay
        self.currentTime = currentTime
    }
}

// MARK: - Media Control Commands

public struct CastPlayCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let mediaSessionId: Int

    public init(requestId: Int = 1, mediaSessionId: Int) {
        self.type = "PLAY"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

public struct CastPauseCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let mediaSessionId: Int

    public init(requestId: Int = 1, mediaSessionId: Int) {
        self.type = "PAUSE"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

public struct CastMediaStopCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let mediaSessionId: Int

    public init(requestId: Int = 1, mediaSessionId: Int) {
        self.type = "STOP"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

public struct CastSeekCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let mediaSessionId: Int
    public let currentTime: Double
    public let resumeState: String?

    public init(
        requestId: Int = 1,
        mediaSessionId: Int,
        currentTime: Double,
        resumeState: String? = "PLAYBACK_START"
    ) {
        self.type = "SEEK"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
        self.currentTime = currentTime
        self.resumeState = resumeState
    }
}

public struct CastVolume: Codable, Sendable, Equatable {
    public let level: Float?
    public let muted: Bool?

    public init(level: Float? = nil, muted: Bool? = nil) {
        self.level = level
        self.muted = muted
    }
}

public struct CastSetVolumeCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let volume: CastVolume

    public init(requestId: Int = 1, volume: CastVolume) {
        self.type = "SET_VOLUME"
        self.requestId = requestId
        self.volume = volume
    }
}

public struct CastMediaGetStatusCommand: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int
    public let mediaSessionId: Int?

    public init(requestId: Int = 1, mediaSessionId: Int? = nil) {
        self.type = "GET_STATUS"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

// MARK: - Receiver & Media Status Response Parsers

public struct CastReceiverAppNamespace: Codable, Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct CastReceiverApplication: Codable, Sendable, Equatable {
    public let appId: String
    public let displayName: String?
    public let sessionId: String
    public let statusText: String?
    public let transportId: String
    public let isIdleScreen: Bool?
    public let namespaces: [CastReceiverAppNamespace]?

    public init(
        appId: String,
        displayName: String? = nil,
        sessionId: String,
        statusText: String? = nil,
        transportId: String,
        isIdleScreen: Bool? = nil,
        namespaces: [CastReceiverAppNamespace]? = nil
    ) {
        self.appId = appId
        self.displayName = displayName
        self.sessionId = sessionId
        self.statusText = statusText
        self.transportId = transportId
        self.isIdleScreen = isIdleScreen
        self.namespaces = namespaces
    }
}

public struct CastReceiverStatusItem: Codable, Sendable, Equatable {
    public let applications: [CastReceiverApplication]?
    public let isStandBy: Bool?
    public let volume: CastVolume?

    public init(
        applications: [CastReceiverApplication]? = nil,
        isStandBy: Bool? = nil,
        volume: CastVolume? = nil
    ) {
        self.applications = applications
        self.isStandBy = isStandBy
        self.volume = volume
    }
}

public struct CastReceiverStatusResponse: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int?
    public let status: CastReceiverStatusItem?

    public init(
        type: String = "RECEIVER_STATUS",
        requestId: Int? = nil,
        status: CastReceiverStatusItem? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.status = status
    }
}

public struct CastMediaStatusItem: Codable, Sendable, Equatable {
    public let mediaSessionId: Int
    public let playbackRate: Double?
    public let playerState: String
    public let currentTime: Double?
    public let idleReason: String?
    public let volume: CastVolume?
    public let media: CastMediaInfo?

    public init(
        mediaSessionId: Int,
        playbackRate: Double? = nil,
        playerState: String,
        currentTime: Double? = nil,
        idleReason: String? = nil,
        volume: CastVolume? = nil,
        media: CastMediaInfo? = nil
    ) {
        self.mediaSessionId = mediaSessionId
        self.playbackRate = playbackRate
        self.playerState = playerState
        self.currentTime = currentTime
        self.idleReason = idleReason
        self.volume = volume
        self.media = media
    }
}

public struct CastMediaStatusResponse: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int?
    public let status: [CastMediaStatusItem]

    public init(
        type: String = "MEDIA_STATUS",
        requestId: Int? = nil,
        status: [CastMediaStatusItem] = []
    ) {
        self.type = type
        self.requestId = requestId
        self.status = status
    }
}

public struct CastGenericResponse: Codable, Sendable, Equatable {
    public let type: String
    public let requestId: Int?

    public init(type: String, requestId: Int? = nil) {
        self.type = type
        self.requestId = requestId
    }
}
