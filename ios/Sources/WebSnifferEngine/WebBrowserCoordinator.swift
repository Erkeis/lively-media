// [Intent] MainActor WebBrowserCoordinator managing WKWebView lifecycle, media stream sniffing, and playback/download actions
import Foundation
import SwiftUI
import WebKit
import CoreStorage
import PlaybackEngine
import CastEngine

@MainActor
public final class WebBrowserCoordinator: NSObject, ObservableObject, WKScriptMessageHandler {
    public static let shared = WebBrowserCoordinator()

    @Published public var currentURLString: String = "https://apple.com"
    @Published public var pageTitle: String = ""
    @Published public var isLoading: Bool = false
    @Published public var detectedStreams: [DetectedStreamItem] = []
    @Published public var showStreamActionSheet: Bool = false
    @Published public var selectedStream: DetectedStreamItem?

    private let playbackCoordinator: PlaybackCoordinator
    private let castCoordinator: CastCoordinator

    public init(
        playbackCoordinator: PlaybackCoordinator = .shared,
        castCoordinator: CastCoordinator = .shared
    ) {
        self.playbackCoordinator = playbackCoordinator
        self.castCoordinator = castCoordinator
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == MediaSnifferScript.handlerName,
              let body = message.body as? [String: Any],
              let streamURLString = body["streamURL"] as? String,
              let streamURL = URL(string: streamURLString),
              let pageURLString = body["pageURL"] as? String,
              let pageURL = URL(string: pageURLString) else {
            return
        }

        let title = (body["title"] as? String) ?? "Detected Stream"
        let isHLS = (body["isHLS"] as? Bool) ?? false
        let format = isHLS ? "m3u8" : (streamURL.pathExtension.isEmpty ? "mp4" : streamURL.pathExtension)

        let item = DetectedStreamItem(
            streamURL: streamURL,
            pageURL: pageURL,
            title: title,
            containerFormat: format,
            isLiveHLS: isHLS
        )

        if !detectedStreams.contains(where: { $0.streamURL == streamURL }) {
            detectedStreams.append(item)
            selectedStream = item
            showStreamActionSheet = true
        }
    }

    public func playStreamInApp(_ stream: DetectedStreamItem) {
        let mediaItem = MediaItem(
            title: stream.title,
            filePath: stream.streamURL.absoluteString,
            fileName: stream.streamURL.lastPathComponent,
            fileSize: 0,
            duration: 0,
            mediaType: .video,
            containerFormat: stream.containerFormat
        )
        Task {
            await playbackCoordinator.playItem(mediaItem)
        }
    }

    public func castStreamToTV(_ stream: DetectedStreamItem) {
        let mediaItem = MediaItem(
            title: stream.title,
            filePath: stream.streamURL.absoluteString,
            fileName: stream.streamURL.lastPathComponent,
            fileSize: 0,
            duration: 0,
            mediaType: .video,
            containerFormat: stream.containerFormat
        )
        Task {
            if let firstDevice = castCoordinator.availableDevices.first {
                try? await castCoordinator.castCurrentItem(to: firstDevice)
            }
        }
    }

    public func clearStreams() {
        detectedStreams.removeAll()
        selectedStream = nil
        showStreamActionSheet = false
    }
}
