// [Intent] Main App Entrypoint for Swift Playgrounds on iPadOS and Xcode on macOS
import SwiftUI
import CoreStorage
import MetadataEngine
import TransferServer
import FileManagerCore
import PlaybackEngine
import PlayerUI
import CastEngine
import WebSnifferEngine
import DownloadManagerEngine
import PodcastEngine

@main
public struct LivelyMediaApp: App {
    @StateObject private var playbackCoordinator = PlaybackCoordinator.shared
    @StateObject private var castCoordinator = CastCoordinator.shared
    @StateObject private var browserCoordinator = WebBrowserCoordinator.shared

    public init() {
        // Initialize SQLite Database and background audio session
        _ = DatabaseManager.shared
        try? AudioSessionManager.shared.configurePlaybackSession()
    }

    public var body: some Scene {
        WindowGroup {
            MainSplitNavigationView()
                .environmentObject(playbackCoordinator)
                .environmentObject(castCoordinator)
                .environmentObject(browserCoordinator)
                .preferredColorScheme(.dark)
        }
    }
}
