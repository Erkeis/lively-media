// [Intent] Root adaptive navigation container supporting iPadOS 3-column NavigationSplitView and iPhone TabBar
import SwiftUI
import CoreStorage
import PlaybackEngine

public enum NavigationSection: String, CaseIterable, Identifiable {
    case library = "Library"
    case audio = "Music"
    case video = "Movies"
    case playlists = "Playlists"
    case wifiTransfer = "Wi-Fi Share"
    case testServer = "Test Server"
    case settings = "Settings"

    public var id: String { rawValue }
    public var iconName: String {
        switch self {
        case .library: return "square.grid.2x2.fill"
        case .audio: return "music.note"
        case .video: return "film.fill"
        case .playlists: return "list.bullet.rectangle.portrait.fill"
        case .wifiTransfer: return "wifi"
        case .testServer: return "server.rack"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MainSplitNavigationView: View {
    @StateObject private var coordinator = PlaybackCoordinator.shared
    @State private var selectedSection: NavigationSection? = .library
    @State private var mockItems: [MediaItem] = [
        MediaItem(title: "Master Audio Session", filePath: "/m/1.flac", fileName: "1.flac", fileSize: 35_000_000, duration: 320, mediaType: .audio, containerFormat: "flac", artist: "Obsidian Duo", album: "Acoustic Lab"),
        MediaItem(title: "Cinema 4K HDR Demo", filePath: "/v/demo.mp4", fileName: "demo.mp4", fileSize: 1_200_000_000, duration: 180, mediaType: .video, containerFormat: "mp4", codec: "HEVC")
    ]

    public init() {}

    public var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            ipadSplitLayout
        } else {
            iphoneTabLayout
        }
        #else
        ipadSplitLayout
        #endif
    }

    // iPad Air 5 3-Column Split View Layout
    private var ipadSplitLayout: some View {
        NavigationSplitView {
            // Sidebar Column
            List(NavigationSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.iconName)
                        .foregroundColor(selectedSection == section ? .studioAmber : .white)
                }
                .listRowBackground(selectedSection == section ? Color.obsidianElevated : Color.clear)
            }
            .navigationTitle("Obsidian Studio")
            .background(Color.obsidianSurface)
        } content: {
            // Media Grid Content Column
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)], spacing: 16) {
                    ForEach(mockItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.obsidianElevated)
                                Image(systemName: item.mediaType == .video ? "film.fill" : "music.note")
                                    .font(.system(size: 36))
                                    .foregroundColor(.studioAmber)
                            }
                            .frame(height: 140)

                            Text(item.title)
                                .font(.studioBody)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text("\(item.containerFormat.uppercased()) • \(Int(item.duration))s")
                                .font(.studioMonoSpec)
                                .foregroundColor(.studioSlate)
                        }
                        .padding(12)
                        .obsidianCard()
                        .onTapGesture {
                            Task { await coordinator.playItem(item) }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(selectedSection?.rawValue ?? "Library")
            .background(Color.obsidianBackground)
        } detail: {
            // Inspector Column
            ZStack {
                Color.obsidianSurface.ignoresSafeArea()
                if let item = coordinator.currentItem {
                    VStack(spacing: 16) {
                        Text("File Inspector")
                            .font(.studioSection)
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title: \(item.title)").foregroundColor(.white)
                            Text("Codec: \(item.codec ?? "Standard")").foregroundColor(.studioSlate)
                            Text("Format: \(item.containerFormat.uppercased())").foregroundColor(.studioAmber)
                            Text("Size: \(item.fileSize / 1_000_000) MB").foregroundColor(.studioSlate)
                        }
                        .font(.studioSecondary)
                        .padding(16)
                        .obsidianCard()

                        Spacer()
                    }
                    .padding(20)
                } else {
                    Text("Select a media file to inspect")
                        .foregroundColor(.studioSlate)
                }
            }
        }
        .sheet(isPresented: $coordinator.isFullscreenAudioPresented) {
            AudioPlayerModalView(coordinator: coordinator)
        }
        .fullScreenCover(isPresented: $coordinator.isFullscreenVideoPresented) {
            VideoPlayerOverlayView(coordinator: coordinator)
        }
    }

    // iPhone Bottom Tab Bar Layout
    private var iphoneTabLayout: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedSection) {
                // Library Tab
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(mockItems) { item in
                            HStack(spacing: 14) {
                                Image(systemName: item.mediaType == .video ? "film.fill" : "music.note")
                                    .foregroundColor(.studioAmber)
                                    .frame(width: 40, height: 40)
                                    .background(Color.obsidianElevated)
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.studioBody).foregroundColor(.white)
                                    Text(item.artist ?? item.containerFormat.uppercased()).font(.studioSecondary).foregroundColor(.studioSlate)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .obsidianCard()
                            .onTapGesture {
                                Task { await coordinator.playItem(item) }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100) // Padding for floating mini player
                }
                .background(Color.obsidianBackground)
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2.fill")
                }
                .tag(NavigationSection.library)

                // Files Tab
                Text("Files Ingestion").tabItem { Label("Files", systemImage: "folder.fill") }.tag(NavigationSection.audio)

                // Wi-Fi Share Tab
                Text("Wi-Fi Transfer Server").tabItem { Label("Wi-Fi Share", systemImage: "wifi") }.tag(NavigationSection.wifiTransfer)

                // Settings Tab
                Text("Settings").tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(NavigationSection.settings)
            }

            // Floating Mini-Player Dock
            MiniPlayerView(coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.isFullscreenAudioPresented) {
            AudioPlayerModalView(coordinator: coordinator)
        }
        .fullScreenCover(isPresented: $coordinator.isFullscreenVideoPresented) {
            VideoPlayerOverlayView(coordinator: coordinator)
        }
    }
}
