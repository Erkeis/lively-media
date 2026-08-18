// [Intent] High-performance async metadata parser utilizing AVFoundation AVURLAsset modern concurrency APIs
import Foundation
import AVFoundation
import CoreStorage

public protocol MetadataParserProtocol: Sendable {
    func parseAudio(url: URL) async throws -> AudioMetadata
    func parseVideo(url: URL) async throws -> VideoMetadata
    func createMediaItem(from url: URL) async throws -> MediaItem
}

public final class MetadataParser: MetadataParserProtocol {
    public init() {}

    public func parseAudio(url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)

        var metadata = AudioMetadata(duration: duration.isFinite ? duration : 0.0)

        let metadataItems = try await asset.load(.metadata)
        for item in metadataItems {
            guard let key = item.commonKey?.rawValue ?? (item.key as? String) else { continue }
            let stringVal = try? await item.load(.stringValue)
            let dataVal = try? await item.load(.dataValue)

            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue:
                metadata.title = stringVal
            case AVMetadataKey.commonKeyArtist.rawValue:
                metadata.artist = stringVal
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                metadata.album = stringVal
            case AVMetadataKey.commonKeyType.rawValue:
                metadata.genre = stringVal
            case AVMetadataKey.commonKeyArtwork.rawValue:
                metadata.artworkData = dataVal
            default:
                break
            }
        }

        // Parse track format specs if available
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let firstTrack = audioTracks.first {
            let descriptions = try await firstTrack.load(.formatDescriptions)
            if let desc = descriptions.first {
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                if let asbd = basic?.pointee {
                    metadata.sampleRate = asbd.mSampleRate
                    metadata.channelCount = Int(asbd.mChannelsPerFrame)
                    metadata.bitDepth = Int(asbd.mBitsPerChannel)
                }
            }
        }

        return metadata
    }

    public func parseVideo(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)

        var metadata = VideoMetadata(duration: duration.isFinite ? duration : 0.0)

        // Video track extraction
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let videoTrack = videoTracks.first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let descriptions = try await videoTrack.load(.formatDescriptions)
            var codecString = "H.264"
            if let desc = descriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                codecString = String(format: "%c%c%c%c",
                                     (mediaSubType >> 24) & 0xff,
                                     (mediaSubType >> 16) & 0xff,
                                     (mediaSubType >> 8) & 0xff,
                                     mediaSubType & 0xff).trimmingCharacters(in: .whitespaces)
            }
            metadata.videoTrack = VideoTrackInfo(
                width: Int(naturalSize.width),
                height: Int(naturalSize.height),
                frameRate: nominalFrameRate,
                codec: codecString
            )
        }

        // Subtitles & Audio streams
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        metadata.audioTrackNames = audioTracks.enumerated().map { "Audio Track \($0.offset + 1)" }

        let subtitleTracks = try await asset.loadTracks(withMediaType: .subtitle)
        metadata.subtitleTrackNames = subtitleTracks.enumerated().map { "Subtitle \($0.offset + 1)" }

        return metadata
    }

    public func createMediaItem(from url: URL) async throws -> MediaItem {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attributes[.size] as? Int64) ?? 0

        let isVideo = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv"].contains(ext)
        let mediaType: MediaType = isVideo ? .video : .audio

        if isVideo {
            let meta = (try? await parseVideo(url: url)) ?? VideoMetadata(duration: 0.0)
            return MediaItem(
                title: meta.title ?? url.deletingPathExtension().lastPathComponent,
                filePath: url.path,
                fileName: fileName,
                fileSize: fileSize,
                duration: meta.duration,
                mediaType: .video,
                containerFormat: ext,
                codec: meta.videoTrack?.codec
            )
        } else {
            let meta = (try? await parseAudio(url: url)) ?? AudioMetadata(duration: 0.0)
            return MediaItem(
                title: meta.title ?? url.deletingPathExtension().lastPathComponent,
                filePath: url.path,
                fileName: fileName,
                fileSize: fileSize,
                duration: meta.duration,
                mediaType: .audio,
                containerFormat: ext,
                artist: meta.artist,
                album: meta.album,
                genre: meta.genre,
                trackNumber: meta.trackNumber
            )
        }
    }
}
