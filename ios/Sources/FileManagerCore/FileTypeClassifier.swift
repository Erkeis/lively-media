// [Intent] High-performance file type classification for audio, video, subtitle, and stream playlist files
import Foundation
import CoreStorage

public enum FileCategory: Sendable {
    case audio(format: String)
    case video(format: String)
    case subtitle(format: String)
    case streamPlaylist(format: String)
    case unsupported
}

public struct FileTypeClassifier: Sendable {
    public static let supportedAudioExtensions: Set<String> = [
        "mp3", "flac", "m4a", "aac", "wav", "alac", "aiff", "ogg", "opus", "wma", "ape"
    ]

    public static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "ts", "3gp"
    ]

    public static let supportedSubtitleExtensions: Set<String> = [
        "srt", "ass", "ssa", "vtt", "sub"
    ]

    public static let supportedStreamExtensions: Set<String> = [
        "m3u8", "m3u", "pls"
    ]

    public static func classify(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if supportedAudioExtensions.contains(ext) {
            return .audio(format: ext)
        } else if supportedVideoExtensions.contains(ext) {
            return .video(format: ext)
        } else if supportedSubtitleExtensions.contains(ext) {
            return .subtitle(format: ext)
        } else if supportedStreamExtensions.contains(ext) {
            return .streamPlaylist(format: ext)
        } else {
            return .unsupported
        }
    }
}
