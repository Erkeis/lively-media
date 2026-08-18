# CHANGELOG

## [Phase 4: In-App Browser & Background Downloader] - 2026-08-17
### Added
- **`WebSnifferEngine`**:
  - `MediaSnifferScript` injected JavaScript for HTML5 `<video>`, `<audio>`, `.m3u8` (HLS), and MP4 stream detection.
  - `DetectedStreamItem` model for intercepted streams.
  - `WebBrowserCoordinator` MainActor coordinator managing WKWebView, stream sniffing, and playback/cast/download actions.
  - `InAppBrowserView` SwiftUI browser tab with address bar and floating Obsidian Studio action sheet.
  - `WebSnifferEngineTests` unit test suite.
- **`DownloadManagerEngine`**:
  - `DownloadTaskItem` and `DownloadState` queue models.
  - `BackgroundDownloadManager` with `URLSessionConfiguration.background`, pause/resume recovery, and auto-indexing into SQLite (`MediaRepository`).
  - `DownloadManagerEngineTests` unit test suite.
- **`PodcastEngine`**:
  - `PodcastChannel` and `PodcastChannelItem` models.
  - `PodcastFeedParser` extracting RSS 2.0 / iTunes XML enclosures and metadata via `XMLParser`.
  - `PodcastEngineTests` unit test suite.

## [Phase 3: Casting & Test Server Integration] - 2026-08-17
### Added
- **`CastEngine`**:
  - `CastTarget`, `CastConnectionState`, and `CastDevice` models.
  - `AirPlayManager` monitoring `AVAudioSession` AirPlay 2 routes.
  - `ChromecastStreamBridge` generating local HTTP 206 stream URLs (`http://<local-ip>:8080/stream/<filename>`) and media payloads for Google Cast.
  - `ChromecastService` managing Google Cast discovery, socket sessions, and remote playback.
  - `CastCoordinator` MainActor coordinator binding AirPlay 2, Google Cast, and local player.
  - `CastEngineTests` unit test suite.
- **`TestServerClient`**:
  - `ServerConfig` supporting local LAN IP and Tailscale mesh VPN MagicDNS hosts.
  - `WebDAVClient` for remote file browsing and test fixture resolution.
  - `HTTPStreamClient` for byte-range (`HTTP 206`) seeking verification.
  - `MockPodcastClient` for RSS 2.0 / iTunes XML podcast feed fetching.
  - `TestServerClientTests` unit test suite.

## [Phase 2: Playback Engines & Player UI] - 2026-08-17
### Added
- **`PlaybackEngine`**:
  - `MediaPlayerProtocol` and `TrackOption` common player interfaces.
  - `AVPlayerAdapter` primary hardware-accelerated engine with periodic time observers and PiP support.
  - `KSPlayerAdapter` secondary universal engine for MKV/WebM/DTS and SSA/ASS subtitles.
  - `AudioSessionManager` managing `AVAudioSession.playback` lifecycle, interruptions (Calls/Siri), and AirPods route changes.
  - `NowPlayingManager` synchronizing `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` controls.
  - `PlaybackCoordinator` MainActor state machine managing active engine routing, queue navigation, and SQLite playback bookmarks.
  - `PlaybackEngineTests` unit test suite.
- **`PlayerUI`**:
  - `ObsidianTheme` SwiftUI design tokens, typography, and card modifiers.
  - `WaveformScrubberView` interactive 100-bar amplitude waveform scrubber with drag seeking and haptic feedback.
  - `EqualizerView` 10-band graphic equalizer with 7 master presets.
  - `SyncedLyricsView` auto-scrolling karaoke-style synchronized lyrics.
  - `MiniPlayerView` floating glass dock with Studio Amber progress indicator.
  - `AudioPlayerModalView` fullscreen audio console with artwork glow, lyrics, EQ, and volume slider.
  - `VideoPlayerOverlayView` 120Hz gesture video player with vertical brightness/volume split HUD and double-tap 10s skip ripple.
  - `MainSplitNavigationView` adaptive 3-column `NavigationSplitView` for iPad Air 5 and TabBar for iPhone.
  - `PlayerUITests` unit test suite.

## [Phase 1: Core Foundation & Ingestion] - 2026-08-17
### Added
- **Modular Swift Package Structure (`LivelyMediaCore`)**:
  - `ios/Package.swift`: Swift 6 / iOS 18.0+ / iPadOS 18.0+ package targeting `CoreStorage`, `MetadataEngine`, `TransferServer`, and `FileManagerCore`.
- **`CoreStorage`**:
  - `MediaItem`, `Playlist`, `PlaylistItem`, `Bookmark` GRDB records.
  - `DatabaseMigrations` with indexed `media_items`, `playlists`, and `bookmarks` tables.
  - `DatabaseManager` thread-safe connection pool.
  - `MediaRepository` (async CRUD, pattern search, favorite toggle, position update).
  - `PlaylistRepository` (lifecycle, ordering, and relational join queries).
  - `DatabaseTests` unit test suite.
- **`MetadataEngine`**:
  - `AudioMetadata` & `VideoMetadata` models.
  - `MetadataParser` using modern async `AVURLAsset` concurrency APIs.
  - `WaveformGenerator` producing 100-sample normalized amplitude arrays for zero-lag UI waveform scrubbing.
  - `MetadataTests` unit test suite.
- **`TransferServer`**:
  - `WebAssets` containing the full Obsidian Studio Glassmorphism Web UI (drag-and-drop file/folder upload, real-time chunked progress bars).
  - `QRCodePayload` for instant mobile connection QR codes.
  - `WebTransferServer` (FlyingFox async HTTP server supporting `/api/files`, `/api/upload`, and `/stream/*` HTTP 206 Partial Content range requests).
  - `TransferServerTests` unit test suite.
- **`FileManagerCore`**:
  - `FileTypeClassifier` categorizing audio, video, subtitle, and stream formats.
  - `SecurityScopedBookmarkManager` for external USB SSDs and iCloud Drive folders.
  - `LocalFileManager` with recursive indexing and reactive `DispatchSourceFileSystemObject` directory monitoring.
  - `FileManagerTests` unit test suite.
- **Documentation**:
  - `docs/ARCHITECTURE.md`, `docs/DESIGN.md`, `docs/ROADMAP.md`, `docs/SERVER.md`.
  - `GEMINI.md` project constitution and directory-level rule files.
