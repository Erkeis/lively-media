// [Intent] Structured metadata extracted from video containers (MP4, MOV, MKV)
import Foundation

public struct VideoTrackInfo: Sendable, Codable {
    public var width: Int
    public var height: Int
    public var frameRate: Float
    public var codec: String

    public init(width: Int, height: Int, frameRate: Float, codec: String) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
    }
}

public struct VideoMetadata: Sendable, Codable {
    public var title: String?
    public var duration: Double
    public var videoTrack: VideoTrackInfo?
    public var audioTrackNames: [String]
    public var subtitleTrackNames: [String]
    public var thumbnailData: Data?

    public init(
        title: String? = nil,
        duration: Double = 0.0,
        videoTrack: VideoTrackInfo? = nil,
        audioTrackNames: [String] = [],
        subtitleTrackNames: [String] = [],
        thumbnailData: Data? = nil
    ) {
        self.title = title
        self.duration = duration
        self.videoTrack = videoTrack
        self.audioTrackNames = audioTrackNames
        self.subtitleTrackNames = subtitleTrackNames
        self.thumbnailData = thumbnailData
    }
}
