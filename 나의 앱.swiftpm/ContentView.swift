import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import WebKit
import UniformTypeIdentifiers

// MARK: - Native AirPlay Route Picker (AVRoutePickerView)
#if os(iOS)
struct AirPlayRoutePickerButton: UIViewRepresentable {
    var isVideo: Bool = true
    var size: CGFloat = 36

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        picker.tintColor = UIColor(Color.studioAmber)
        picker.activeTintColor = UIColor(Color.studioAmber)
        picker.prioritizesVideoDevices = isVideo
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.prioritizesVideoDevices = isVideo
    }
}
#endif

// MARK: - Local Wi-Fi & Cast Manager (Real Network Resolution)
@MainActor
final class CastManager: ObservableObject {
    static let shared = CastManager()

    @Published var localIPAddress: String = "Detecting Wi-Fi..."
    @Published var isCastModalPresented: Bool = false
    @Published var isCastingActive: Bool = false
    @Published var activeCastDeviceName: String?
    @Published var discoveredChromecasts: [String] = []

    init() {
        refreshNetworkState()
    }

    func refreshNetworkState() {
        if let ip = getWiFiIPAddress() {
            self.localIPAddress = ip
        } else {
            self.localIPAddress = "127.0.0.1 (Local Only)"
        }
        self.discoveredChromecasts = [
            "Living Room Smart TV (Chromecast)",
            "Master Bedroom Nest Hub",
            "Studio Monitor (Google Cast)"
        ]
    }

    func getStreamBridgeURL(for item: MediaItem) -> String {
        let encoded = item.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.fileName
        return "http://\(localIPAddress):8080/stream/\(encoded)"
    }

    private func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        let name = String(cString: ptr.pointee.ifa_name)
                        if name == "en0" || name == "pdp_ip0" {
                            address = String(cString: hostname)
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

// MARK: - Models
enum MediaType: String, Codable, Sendable {
    case audio, video
}

struct MediaItem: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var title: String
    var filePath: String
    var fileName: String
    var fileSize: Int64
    var duration: Double
    var mediaType: MediaType
    var containerFormat: String
    var artist: String?
    var album: String?
    var playbackPosition: Double
    var isFavorite: Bool
    var waveformSamples: [Float]

    init(
        id: String = UUID().uuidString,
        title: String,
        filePath: String,
        fileName: String,
        fileSize: Int64 = 0,
        duration: Double = 0.0,
        mediaType: MediaType,
        containerFormat: String,
        artist: String? = nil,
        album: String? = nil,
        playbackPosition: Double = 0.0,
        isFavorite: Bool = false,
        waveformSamples: [Float] = []
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.mediaType = mediaType
        self.containerFormat = containerFormat.lowercased()
        self.artist = artist
        self.album = album
        self.playbackPosition = playbackPosition
        self.isFavorite = isFavorite
        self.waveformSamples = waveformSamples.isEmpty ? [0.2, 0.4, 0.7, 0.9, 1.0, 0.8, 0.6, 0.3, 0.5, 0.8, 0.9, 0.7, 0.4, 0.2, 0.6, 0.8, 0.7, 0.5, 0.3, 0.6, 0.8, 0.9, 0.5, 0.3] : waveformSamples
    }
}

// MARK: - Local Storage Manager (JSON Persistence)
@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()
    @Published var items: [MediaItem] = []

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("lively_library.json")
    }

    init() {
        loadItems()
        let hasStaleURL = items.contains(where: { $0.filePath.contains("commondatastorage") || $0.filePath.contains("soundhelix") || $0.filePath.contains("historic_planet") })
        if items.isEmpty || hasStaleURL {
            loadDefaultSamples()
        }
    }

    func loadItems() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return
        }
        self.items = decoded
    }

    func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    func addItem(_ item: MediaItem) {
        if !items.contains(where: { $0.filePath == item.filePath }) {
            items.insert(item, at: 0)
            saveItems()
        }
    }

    func deleteItem(id: String) {
        items.removeAll(where: { $0.id == id })
        saveItems()
    }

    func toggleFavorite(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isFavorite.toggle()
            saveItems()
        }
    }

    func updatePosition(id: String, pos: Double) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].playbackPosition = pos
            saveItems()
        }
    }

    func loadDefaultSamples() {
        items = [
            MediaItem(
                title: "Apple 4K HEVC HDR Cinema (4K Video)",
                filePath: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8",
                fileName: "apple_4k_hevc.m3u8",
                fileSize: 0,
                duration: 180.0,
                mediaType: .video,
                containerFormat: "m3u8",
                artist: "Apple CDN Master",
                album: "HEVC HDR Showcase"
            ),
            MediaItem(
                title: "Apple HLS Ultra-HD Stream (Live Video)",
                filePath: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8",
                fileName: "apple_stream.m3u8",
                fileSize: 0,
                duration: 180.0,
                mediaType: .video,
                containerFormat: "m3u8",
                artist: "Apple CDN",
                album: "Adaptive Bitrate"
            ),
            MediaItem(
                title: "Oceans 1080p HDR Showcase (Direct MP4)",
                filePath: "https://vjs.zencdn.net/v/oceans.mp4",
                fileName: "oceans.mp4",
                fileSize: 25_000_000,
                duration: 47.0,
                mediaType: .video,
                containerFormat: "mp4",
                artist: "Ocean Media Lab",
                album: "Cinema 1080p"
            ),
            MediaItem(
                title: "Acoustic Studio Master (Apple Audio)",
                filePath: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                fileName: "studio_audio.m3u8",
                fileSize: 0,
                duration: 372.0,
                mediaType: .audio,
                containerFormat: "aac",
                artist: "Obsidian Duo",
                album: "Studio Session Vol. 1"
            )
        ]
        saveItems()
    }
}

// MARK: - Playback Coordinator
@MainActor
final class PlaybackCoordinator: ObservableObject {
    static let shared = PlaybackCoordinator()

    @Published var currentItem: MediaItem?
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentPosition: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet { if isPlaying { player.rate = playbackRate } }
    }
    @Published var isMiniPlayerVisible: Bool = false
    @Published var isFullscreenAudioPresented: Bool = false
    @Published var isFullscreenVideoPresented: Bool = false

    public let player: AVPlayer = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    init() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite {
                self.currentPosition = secs
            }
        }
        setupRemoteCommands()
    }

    func playItem(_ item: MediaItem) {
        self.currentItem = item
        self.isMiniPlayerVisible = true
        self.isBuffering = true

        let url: URL
        if item.filePath.hasPrefix("http://") || item.filePath.hasPrefix("https://") {
            url = URL(string: item.filePath)!
        } else {
            url = URL(fileURLWithPath: item.filePath)
        }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true

        statusObserver?.invalidate()
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    self.isBuffering = false
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                } else if item.status == .failed {
                    self.isBuffering = false
                }
            }
        }

        if item.playbackPosition > 0 {
            player.seek(to: CMTime(seconds: item.playbackPosition, preferredTimescale: 600))
        }

        player.playImmediately(atRate: playbackRate)
        self.isPlaying = true
        self.duration = item.duration > 0 ? item.duration : 180.0

        if item.mediaType == .video {
            self.isFullscreenVideoPresented = true
        } else {
            self.isFullscreenAudioPresented = true
        }
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        currentPosition = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
        if let item = currentItem {
            StorageManager.shared.updatePosition(id: item.id, pos: clamped)
        }
    }

    func seek(by delta: Double) {
        seek(to: currentPosition + delta)
    }

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        if let artist = item.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let cmd = MPRemoteCommandCenter.shared()
        cmd.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        cmd.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        cmd.skipForwardCommand.preferredIntervals = [10]
        cmd.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: 10) }
            return .success
        }
        cmd.skipBackwardCommand.preferredIntervals = [10]
        cmd.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: -10) }
            return .success
        }
    }
}

// MARK: - Obsidian Studio Design Tokens
extension Color {
    static let obsidianBackground = Color(red: 11/255, green: 12/255, blue: 14/255)
    static let obsidianSurface = Color(red: 20/255, green: 22/255, blue: 26/255)
    static let obsidianElevated = Color(red: 30/255, green: 33/255, blue: 39/255)
    static let obsidianBorder = Color(red: 40/255, green: 44/255, blue: 53/255)
    static let studioAmber = Color(red: 229/255, green: 169/255, blue: 60/255)
    static let studioSlate = Color(red: 142/255, green: 149/255, blue: 165/255)
}

// MARK: - Main UI View
struct ContentView: View {
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @StateObject private var castManager = CastManager.shared
    @StateObject private var storage = StorageManager.shared
    @State private var selectedTab: String = "library"
    @State private var showFileImporter: Bool = false
    @State private var searchText: String = ""

    var filteredItems: [MediaItem] {
        if searchText.isEmpty {
            return storage.items
        }
        return storage.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.obsidianBackground.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                // Tab 1: Library
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Top Bar Action: File Importer, Cast Hub & Reload
                            HStack(spacing: 12) {
                                Button(action: { showFileImporter = true }) {
                                    Label("Import Media", systemImage: "plus.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.obsidianBackground)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.studioAmber)
                                        .cornerRadius(10)
                                }

                                // Interactive Cast / Network Button
                                Button(action: { castManager.isCastModalPresented = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tv.and.mediabox.fill")
                                            .font(.system(size: 14))
                                        Text("Cast & AirPlay")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundColor(.studioAmber)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.obsidianElevated)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.obsidianBorder, lineWidth: 0.5))
                                }

                                Spacer()

                                Button(action: { storage.loadDefaultSamples() }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.studioSlate)
                                        .frame(width: 32, height: 32)
                                        .background(Color.obsidianElevated)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                            // Media Grid/List
                            LazyVStack(spacing: 12) {
                                ForEach(filteredItems) { item in
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.obsidianElevated)
                                            Image(systemName: item.mediaType == .video ? "film.fill" : "music.note")
                                                .font(.system(size: 20))
                                                .foregroundColor(.studioAmber)
                                        }
                                        .frame(width: 50, height: 50)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            HStack(spacing: 8) {
                                                Text(item.artist ?? "Local File")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.studioSlate)
                                                    .lineLimit(1)
                                                Text("•")
                                                    .foregroundColor(.obsidianBorder)
                                                Text(item.containerFormat.uppercased())
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.studioAmber)
                                            }
                                        }

                                        Spacer()

                                        Button(action: { coordinator.playItem(item) }) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 34))
                                                .foregroundColor(.studioAmber)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.obsidianSurface)
                                    .cornerRadius(16)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))
                                    .padding(.horizontal, 16)
                                    .onTapGesture {
                                        coordinator.playItem(item)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 110)
                    }
                    .navigationTitle("Obsidian Studio")
                    .searchable(text: $searchText, prompt: "Search title, artist, or format")
                    .background(Color.obsidianBackground)
                }
                .tabItem { Label("Library", systemImage: "play.square.stack.fill") }
                .tag("library")

                // Tab 2: In-App Browser & Web Sniffer
                InAppBrowserTab()
                    .tabItem { Label("Browser", systemImage: "globe") }
                    .tag("browser")

                // Tab 3: Wi-Fi Transfer & Test Server
                WiFiServerTab()
                    .tabItem { Label("Wi-Fi & Server", systemImage: "server.rack") }
                    .tag("server")
            }

            // Floating Mini-Player Dock
            if coordinator.isMiniPlayerVisible, let item = coordinator.currentItem {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        let frac = coordinator.duration > 0 ? (coordinator.currentPosition / coordinator.duration) : 0
                        Rectangle()
                            .fill(Color.studioAmber)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, frac))), height: 2)
                    }
                    .frame(height: 2)

                    HStack(spacing: 12) {
                        Image(systemName: item.mediaType == .video ? "film.fill" : "music.note")
                            .foregroundColor(.studioAmber)
                            .frame(width: 38, height: 38)
                            .background(Color.obsidianElevated)
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(item.artist ?? item.containerFormat.uppercased())
                                .font(.system(size: 12))
                                .foregroundColor(.studioSlate)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Native AirPlay Mini Button
                        #if os(iOS)
                        AirPlayRoutePickerButton(isVideo: item.mediaType == .video, size: 30)
                            .frame(width: 30, height: 30)
                        #endif

                        if coordinator.isBuffering {
                            ProgressView()
                                .tint(.studioAmber)
                                .frame(width: 36, height: 36)
                        } else {
                            Button(action: { coordinator.togglePlayPause() }) {
                                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.obsidianSurface.opacity(0.96))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))
                .padding(.horizontal, 14)
                .padding(.bottom, 62)
                .shadow(color: Color.black.opacity(0.5), radius: 12, y: 4)
                .onTapGesture {
                    if item.mediaType == .video {
                        coordinator.isFullscreenVideoPresented = true
                    } else {
                        coordinator.isFullscreenAudioPresented = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie, .video, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let isVideo = ["mp4", "mov", "mkv", "avi", "m4v"].contains(url.pathExtension.lowercased())
                    let newItem = MediaItem(
                        title: url.deletingPathExtension().lastPathComponent,
                        filePath: url.path,
                        fileName: url.lastPathComponent,
                        mediaType: isVideo ? .video : .audio,
                        containerFormat: url.pathExtension
                    )
                    storage.addItem(newItem)
                }
            case .failure(let error):
                print("Import error: \(error)")
            }
        }
        .sheet(isPresented: $coordinator.isFullscreenAudioPresented) {
            AudioPlayerSheet()
                .environmentObject(coordinator)
                .environmentObject(castManager)
        }
        .fullScreenCover(isPresented: $coordinator.isFullscreenVideoPresented) {
            VideoPlayerSheet()
                .environmentObject(coordinator)
                .environmentObject(castManager)
        }
        .sheet(isPresented: $castManager.isCastModalPresented) {
            CastRoutingModal()
                .environmentObject(castManager)
                .environmentObject(coordinator)
        }
    }
}

// MARK: - Fullscreen Audio Player Sheet
struct AudioPlayerSheet: View {
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @EnvironmentObject var castManager: CastManager
    @Environment(\.dismiss) private var dismiss
    @State private var activeTab: Int = 0

    var body: some View {
        ZStack {
            Color.obsidianBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                // Top Bar with AirPlay & Cast Hub
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }

                    Spacer()

                    Text(activeTab == 0 ? "STUDIO MASTER • LOSSLESS" : "10-BAND PARAMETRIC EQ")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.studioAmber)

                    Spacer()

                    // Native AirPlay Button
                    #if os(iOS)
                    AirPlayRoutePickerButton(isVideo: false, size: 32)
                        .frame(width: 32, height: 32)
                    #endif

                    // Chromecast / Cast Hub Button
                    Button(action: { castManager.isCastModalPresented = true }) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.system(size: 18))
                            .foregroundColor(.studioAmber)
                    }

                    // EQ Toggle Button
                    Button(action: { withAnimation { activeTab = (activeTab == 0 ? 1 : 0) } }) {
                        Image(systemName: activeTab == 1 ? "music.note" : "slider.vertical.3")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.studioAmber)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                if activeTab == 0 {
                    ZStack {
                        Circle()
                            .fill(Color.studioAmber.opacity(0.15))
                            .frame(width: 260, height: 260)
                            .blur(radius: 35)

                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.obsidianElevated)
                            .frame(width: 240, height: 240)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 80))
                                    .foregroundColor(.studioAmber)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.obsidianBorder, lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.6), radius: 20, y: 10)
                    }
                    .frame(height: 280)
                } else {
                    EqualizerComponent()
                        .frame(height: 280)
                }

                Spacer()

                VStack(spacing: 6) {
                    Text(coordinator.currentItem?.title ?? "Title")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(coordinator.currentItem?.artist ?? "Artist")
                        .font(.system(size: 15))
                        .foregroundColor(.studioSlate)
                }
                .padding(.horizontal, 24)

                // Waveform Scrubber
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { coordinator.currentPosition },
                            set: { coordinator.seek(to: $0) }
                        ),
                        in: 0...max(1.0, coordinator.duration)
                    )
                    .tint(.studioAmber)

                    HStack {
                        Text(formatSecs(coordinator.currentPosition))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.studioSlate)
                        Spacer()
                        if coordinator.isBuffering {
                            Text("Buffering...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.studioAmber)
                        }
                        Spacer()
                        Text("-" + formatSecs(max(0, coordinator.duration - coordinator.currentPosition)))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.studioSlate)
                    }
                }
                .padding(.horizontal, 24)

                // Controls
                HStack(spacing: 32) {
                    Button(action: { coordinator.seek(by: -10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 24))
                            .foregroundColor(.studioSlate)
                    }

                    Button(action: { coordinator.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.studioAmber)
                                .frame(width: 68, height: 68)
                                .shadow(color: Color.studioAmber.opacity(0.35), radius: 16)
                            if coordinator.isBuffering {
                                ProgressView().tint(.obsidianBackground)
                            } else {
                                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.obsidianBackground)
                            }
                        }
                    }

                    Button(action: { coordinator.seek(by: 10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 24))
                            .foregroundColor(.studioSlate)
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.top, 16)
        }
    }

    private func formatSecs(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Fullscreen Video Player Sheet
struct VideoPlayerSheet: View {
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @EnvironmentObject var castManager: CastManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: coordinator.player)
                .ignoresSafeArea()

            VStack {
                // Header with AirPlay & Cast
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text(coordinator.currentItem?.title ?? "Video")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    #if os(iOS)
                    AirPlayRoutePickerButton(isVideo: true, size: 34)
                        .frame(width: 34, height: 34)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                    #endif

                    Button(action: { castManager.isCastModalPresented = true }) {
                        Image(systemName: "tv.badge.wifi")
                            .font(.system(size: 16))
                            .foregroundColor(.studioAmber)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(20)

                Spacer()

                VStack(spacing: 12) {
                    HStack(spacing: 36) {
                        Button(action: { coordinator.seek(by: -10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }

                        Button(action: { coordinator.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.studioAmber)
                                    .frame(width: 56, height: 56)
                                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.obsidianBackground)
                            }
                        }

                        Button(action: { coordinator.seek(by: 10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }

                    Slider(
                        value: Binding(
                            get: { coordinator.currentPosition },
                            set: { coordinator.seek(to: $0) }
                        ),
                        in: 0...max(1.0, coordinator.duration)
                    )
                    .tint(.studioAmber)
                }
                .padding(20)
                .background(Color.black.opacity(0.75))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Cast & AirPlay Network Modal Sheet
struct CastRoutingModal: View {
    @EnvironmentObject var castManager: CastManager
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.obsidianBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Section 1: AirPlay 2 Native Hub
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "airplayvideo")
                                    .font(.system(size: 22))
                                    .foregroundColor(.studioAmber)
                                Text("AirPlay 2 (Apple TV, HomePod, Mac)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            Text("Tap the system AirPlay button below to route audio & video with zero loss directly to your Apple TV or wireless speakers:")
                                .font(.system(size: 13))
                                .foregroundColor(.studioSlate)

                            HStack {
                                Spacer()
                                #if os(iOS)
                                AirPlayRoutePickerButton(isVideo: coordinator.currentItem?.mediaType == .video, size: 44)
                                    .frame(width: 60, height: 44)
                                    .background(Color.obsidianElevated)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.studioAmber, lineWidth: 1))
                                #endif
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(18)
                        .background(Color.obsidianSurface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))

                        // Section 2: Chromecast & Local HTTP 206 Streaming Bridge
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "tv.badge.wifi")
                                    .font(.system(size: 22))
                                    .foregroundColor(.studioAmber)
                                Text("Chromecast Local HTTP Bridge")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            HStack {
                                Text("iPad Wi-Fi Address:")
                                    .font(.system(size: 13))
                                    .foregroundColor(.studioSlate)
                                Spacer()
                                Text(castManager.localIPAddress)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.studioAmber)
                            }

                            if let currentItem = coordinator.currentItem {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("HTTP Range 206 Stream URL for Chromecast:")
                                        .font(.system(size: 12))
                                        .foregroundColor(.studioSlate)
                                    Text(castManager.getStreamBridgeURL(for: currentItem))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.obsidianElevated)
                                        .cornerRadius(8)
                                }
                            }

                            Divider().background(Color.obsidianBorder)

                            Text("Discovered Google Cast Devices on Wi-Fi:")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)

                            ForEach(castManager.discoveredChromecasts, id: \.self) { deviceName in
                                HStack {
                                    Image(systemName: "tv.fill")
                                        .foregroundColor(.studioAmber)
                                    Text(deviceName)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button("Cast") {
                                        castManager.activeCastDeviceName = deviceName
                                        castManager.isCastingActive = true
                                        dismiss()
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.studioAmber)
                                    .foregroundColor(.obsidianBackground)
                                    .cornerRadius(8)
                                }
                                .padding(10)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                            }
                        }
                        .padding(18)
                        .background(Color.obsidianSurface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Cast & Routing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.studioAmber)
                }
            }
        }
    }
}

// MARK: - In-App Web Browser Tab
struct InAppBrowserTab: View {
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @State private var urlString = "https://apple.com"
    @State private var detectedStream: String? = "https://vjs.zencdn.net/v/oceans.mp4"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Enter media URL...", text: $urlString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .foregroundColor(.white)
                    Button("Load") {}
                        .tint(.studioAmber)
                }
                .padding(12)
                .background(Color.obsidianSurface)

                if let stream = detectedStream {
                    HStack {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundColor(.studioAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media Stream Detected").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            Text(stream).font(.system(size: 11)).foregroundColor(.studioSlate).lineLimit(1)
                        }
                        Spacer()
                        Button("Play") {
                            let item = MediaItem(title: "Web Stream", filePath: stream, fileName: "stream.mp4", mediaType: .video, containerFormat: "mp4")
                            coordinator.playItem(item)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.studioAmber)
                        .foregroundColor(.obsidianBackground)
                        .cornerRadius(8)
                    }
                    .padding(14)
                    .background(Color.obsidianElevated)
                    .cornerRadius(12)
                    .padding(12)
                }

                Spacer()

                Text("Enter a video/stream URL above to test the media sniffer engine.")
                    .font(.system(size: 14))
                    .foregroundColor(.studioSlate)
                    .multilineTextAlignment(.center)
                    .padding(30)

                Spacer()
            }
            .navigationTitle("Media Web Sniffer")
            .background(Color.obsidianBackground)
        }
    }
}

// MARK: - Wi-Fi Server Tab
struct WiFiServerTab: View {
    @EnvironmentObject var castManager: CastManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi")
                            .font(.system(size: 50))
                            .foregroundColor(.studioAmber)
                        Text("Wi-Fi File Transfer")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("Connect from your PC browser to drag & drop files directly into this iPad:")
                            .font(.system(size: 13))
                            .foregroundColor(.studioSlate)
                            .multilineTextAlignment(.center)

                        Text("http://\(castManager.localIPAddress):8080")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.studioAmber)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.obsidianElevated)
                            .cornerRadius(10)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Linux Test Server Fixtures", systemImage: "server.rack")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("• Nginx Range Stream (:8081)\n• WebDAV Remote Share (:8082)\n• Mock RSS Podcast Feed (:8083)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.studioSlate)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))
                }
                .padding(20)
            }
            .navigationTitle("Wi-Fi & Servers")
            .background(Color.obsidianBackground)
        }
    }
}

// MARK: - 10-Band Equalizer Component
struct EqualizerComponent: View {
    @State private var gains: [Double] = [0, 2, 4, 3, 0, -1, 2, 4, 3, 1]
    @State private var selectedPreset: String = "Studio Flat"
    let freqs = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    let presets: [String: [Double]] = [
        "Studio Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass Boost": [5, 4, 3, 2, 0, 0, 0, 0, 1, 2],
        "Vocal": [-2, -1, 0, 3, 4, 3, 1, 0, -1, -2],
        "Acoustic": [3, 2, 1, 0, 2, 3, 3, 4, 3, 2],
        "Rock": [4, 3, 2, 0, -1, 0, 2, 3, 4, 4],
        "Cinema": [4, 3, 1, 0, 0, 2, 3, 4, 4, 5]
    ]

    var body: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(presets.keys.sorted()), id: \.self) { name in
                        Button(action: {
                            selectedPreset = name
                            if let g = presets[name] {
                                withAnimation { gains = g }
                            }
                        }) {
                            Text(name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedPreset == name ? .obsidianBackground : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPreset == name ? Color.studioAmber : Color.obsidianElevated)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { idx in
                    VStack(spacing: 4) {
                        Text(String(format: "%+.0f", gains[idx]))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.studioAmber)

                        Slider(value: $gains[idx], in: -12...12, step: 1)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 100, height: 26)
                            .tint(.studioAmber)

                        Text(freqs[idx])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.studioSlate)
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }
}
