# SYSTEM ARCHITECTURE & MEDIA ENGINE SPECIFICATION

## 1. System Overview
The application is a high-performance, offline-first personal media player engineered for **iOS 18.0+ and iPadOS 18.0+** using **Swift 6 and SwiftUI**. It provides a unified, battery-efficient engine for playing local audio/video, streaming via **AirPlay 2** and **Chromecast**, managing files in-app and via the iOS Files app, and exploring web-based media streams.

### 1.1 Target Hardware & OS Profiles
- **Primary iPhone Target**: **iPhone 11 (iOS 18.7.7)**
  - *Hardware Profile*: Apple A13 Bionic, 4GB RAM, 6.1" Liquid Retina (Notch / Safe Area layout).
  - *Engineering Priority*: Strict memory footprint discipline (< 100MB active) during large library indexing and FLAC/MKV soft-decoding to avoid Jetsam terminations; full support for portrait/landscape notch safe areas.
- **Primary iPadOS Target**: **iPad Air 5th Gen (iPadOS 18.7.8)**
  - *Hardware Profile*: Apple Silicon M1 (8-core CPU/GPU, 8GB RAM), 10.9" Liquid Retina.
  - *Engineering Priority*: Stage Manager fluid multi-window resizing, 3-column `NavigationSplitView`, hardware-accelerated Metal video rendering, and USB-C direct external drive (SSD/Flash) indexing via security-scoped bookmarks.

```mermaid
graph TB
    subgraph UI_Layer [Presentation Layer - SwiftUI]
        MainWindow[NavigationSplitView / Main Tabs]
        AudioModal[Studio Audio Player Modal]
        VideoOverlay[120Hz Gesture Video Player]
        MiniPlayer[Floating Glass Mini-Player Dock]
        BrowserTab[WKWebView Media Stream Sniffer]
        CastSheet[AirPlay & Cast Route Picker]
    end

    subgraph Service_Layer [Coordinator & Services Layer]
        PlaybackCoordinator[Playback Coordinator]
        FileManagerService[File Ingestion & Sandbox Manager]
        CastBridgeService[Chromecast HTTP 206 Bridge & AirPlay]
        DownloadManager[Background URLSession Downloader]
        DatabaseService[SQLite / GRDB Storage Service]
    end

    subgraph Engine_Layer [Media Execution Engines]
        AVPlayerAdapter[AVPlayer Engine (Hardware Accelerated)]
        KSPlayerAdapter[KSPlayer / Metal Engine (Universal Codecs)]
        EmbeddedHTTPServer[Embedded HTTP Server (FlyingFox)]
        MetadataExtractor[AVAsset & ID3 Tag Parser]
    end

    subgraph Storage_Layer [Storage & OS Integration]
        AppSandbox[App Documents / iOS Files App]
        SQLiteDB[(my_project.sqlite Database)]
        SecurityBookmarks[Security-Scoped Bookmark Provider]
        SystemNowPlaying[MPNowPlayingInfoCenter & RemoteCommand]
    end

    UI_Layer --> Service_Layer
    Service_Layer --> Engine_Layer
    Engine_Layer --> Storage_Layer
    Service_Layer --> Storage_Layer
```

---

## 2. Dual Playback Engine Architecture

### 2.1 Playback Protocol Abstraction
To keep UI components decoupled from specific playback frameworks, all player interactions conform to `MediaPlayerProtocol`:

```swift
// [Intent] Common playback protocol decoupling SwiftUI views from underlying decoder engines
protocol MediaPlayerProtocol: AnyObject {
    var state: PlaybackState { get }
    var currentPosition: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var playbackRate: Float { get set }
    var currentItem: MediaItem? { get }
    
    func load(item: MediaItem) async throws
    func play()
    func pause()
    func seek(to position: TimeInterval)
    func setSubtitleTrack(index: Int)
    func setAudioTrack(index: Int)
    func releaseResources()
}
```

### 2.2 Adaptive Engine Routing Logic
```mermaid
graph TD
    MediaInput[Media File Selected] --> Analyze[Container & Codec Inspector]
    Analyze -->|MP4 / MOV / H.264 / HEVC / MP3 / AAC / FLAC| AVEngine[Primary: AVPlayer Engine]
    Analyze -->|MKV / AVI / DTS / Opus / SSA-ASS Subtitles / WebM| KSEngine[Secondary: KSPlayer Metal Engine]
    
    AVEngine --> HWOut[Hardware VideoToolbox & AudioUnit]
    KSEngine --> MetalOut[Metal Shaders & FFmpeg Soft-Decoder]
    
    HWOut --> Display[Unified Player Presentation]
    MetalOut --> Display
```

1. **Primary Engine (AVPlayer / AVFoundation)**:
   - Zero-copy hardware decoding for Apple-native formats.
   - Lowest possible battery consumption.
   - Native Picture-in-Picture (`AVPictureInPictureController`) and native AirPlay 2 video streaming.
2. **Secondary Engine (KSPlayer / Metal + FFmpeg)**:
   - Pure Swift wrapper around FFmpeg and libass with Metal shader rendering.
   - Full support for `.mkv`, `.avi`, `.webm`, DTS audio, and advanced SSA/ASS subtitle styling.
   - Picture-in-Picture supported via `AVSampleBufferDisplayLayer` bridge.

---

## 3. Storage, File Ingestion & Database Architecture

### 3.1 File Ingestion Channels
- **iOS Files App Integration**: Enabled via `UIFileSharingEnabled = true` and `LSSupportsOpeningDocumentsInPlace = true` in `Info.plist`. Files placed in the app's folder are automatically indexed.
- **Embedded Wi-Fi Web Transfer**: Local HTTP web interface allowing desktop browser drag-and-drop file upload (`http://<device-ip>:8080`).
- **External Storage / USB**: `UIDocumentPickerViewController` with security-scoped resource bookmarks.

### 3.2 Database Schema (SQLite / GRDB)
```sql
CREATE TABLE IF NOT EXISTS media_items (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    file_path TEXT NOT NULL UNIQUE,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    duration REAL DEFAULT 0.0,
    media_type TEXT NOT NULL, -- 'audio' or 'video'
    container_format TEXT NOT NULL, -- 'mp4', 'mkv', 'mp3', 'flac'
    codec TEXT,
    artwork_path TEXT,
    artist TEXT,
    album TEXT,
    genre TEXT,
    track_number INTEGER,
    last_played_at INTEGER,
    playback_position REAL DEFAULT 0.0,
    is_favorite INTEGER DEFAULT 0,
    waveform_data BLOB,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlists (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_items (
    playlist_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, media_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bookmarks (
    id TEXT PRIMARY KEY,
    media_id TEXT NOT NULL,
    position REAL NOT NULL,
    title TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (media_id) REFERENCES media_items(id) ON DELETE CASCADE
);
```

---

## 4. Casting & Streaming Architecture

### 4.1 AirPlay 2
- Handled natively through `AVRoutePickerView` and standard `AVPlayerItem` routing.

### 4.2 Pure-Swift Cast V2 Socket Protocol & Local HTTP Range Bridge

#### 4.2.1 Architectural Rationale: Why Pure Swift instead of Closed-Source Binary SDKs
The standard Google Cast iOS SDK (`GoogleCast.xcframework`) is a large, closed-source binary distribution with legacy Objective-C/C++ dependencies. It introduces critical architectural roadblocks for modern multi-device media platforms:
1. **Swift Playgrounds & Toolchain Portability**: Closed-source binary `.xcframework` dependencies cannot be built or linked inside Swift Playgrounds on iPad Air 5 (M1 Apple Silicon) and fail on clean headless Linux/macOS SwiftPM test environments without complex workarounds.
2. **Memory Footprint & Bloat**: Proprietary SDK binaries inject dozens of auxiliary tracking routines and heavy runtime symbols that compromise the app's strict memory ceiling (< 100MB active footprint on iPhone 11).
3. **Swift 6 Concurrency Compliance**: Legacy RunLoop and delegate callbacks in the binary SDK conflict with Swift 6 strict concurrency checks (`@Sendable`, `actor` isolation, and `@MainActor` UI hierarchies).

To maintain zero binary dependencies, absolute cross-platform compilation, and strict Swift 6 concurrency safety, LivelyMedia implements a **Pure-Swift Cast V2 Engine** built on Apple's native `Network.framework` (`NWBrowser` and `NWConnection`) coupled with an embedded async HTTP Range 206 streaming bridge (`FlyingFox`).

#### 4.2.2 Cast V2 Protocol Framing & Channel Architecture

```mermaid
graph TB
    subgraph Discovery_Layer [Discovery & Network Transport]
        mDNS[NWBrowser mDNS Discovery: _googlecast._tcp.local.]
        NWConn[NWConnection TLS Socket: Port 8009]
        TLSConfig[Custom TLS Trust: Bypass Self-Signed Cast Cert Validation]
    end

    subgraph Framing_Layer [Cast V2 Wire Framing]
        Header[4-Byte Big-Endian Length Prefix: UInt32]
        Payload[Serialized CastMessage JSON/Protobuf Payload]
    end

    subgraph Channels [Virtual Namespaces / Channels]
        ConnChan[urn:x-cast:com.google.cast.tp.connection (CONNECT / CLOSE)]
        HeartbeatChan[urn:x-cast:com.google.cast.tp.heartbeat (PING / PONG @ 5s)]
        ReceiverChan[urn:x-cast:com.google.cast.receiver (LAUNCH CC1AD845 / GET_STATUS)]
        MediaChan[urn:x-cast:com.google.cast.media (LOAD / PLAY / PAUSE / SEEK / STATUS)]
    end

    subgraph Bridge_Layer [Local Sandbox Streaming Bridge]
        HTTPBridge[Embedded FlyingFox Server :8080]
        ByteRange[HTTP 206 Partial Content: Range: bytes=X-Y]
        SandboxMedia[App Sandbox Media Files]
    end

    mDNS --> NWConn
    TLSConfig --> NWConn
    NWConn --> Header
    Header --> Payload
    Payload --> ConnChan
    Payload --> HeartbeatChan
    Payload --> ReceiverChan
    Payload --> MediaChan
    MediaChan -.->|Directs to Stream URL| HTTPBridge
    HTTPBridge --> ByteRange
    ByteRange --> SandboxMedia
```

1. **mDNS Device Discovery**:
   - `NWBrowser` scans for Bonjour services of type `_googlecast._tcp` on domain `local.`.
   - Parses TXT records (`fn` for friendly device name, `md` for model name, `id` for device UUID).
2. **TLS Port 8009 Socket Transport**:
   - Establishes a secure TCP socket to the target IP on port `8009` via `NWConnection`.
   - Google Cast hardware uses self-signed X.509 device certificates; the connection configures `sec_protocol_options_set_verify_block` to permit the TLS handshake without failing system CA checks.
3. **Wire Packet Framing**:
   - All messages over the socket are framed with a **4-byte big-endian unsigned integer** specifying the byte length of the following payload, followed by the UTF-8 serialized `CastMessage` payload.
4. **Cast V2 Channel Namespaces**:
   - **Connection Channel** (`urn:x-cast:com.google.cast.tp.connection`): Handles transport session initialization (`{"type": "CONNECT"}`) and teardown (`{"type": "CLOSE"}`).
   - **Heartbeat Channel** (`urn:x-cast:com.google.cast.tp.heartbeat`): Exchanges `PING` and `PONG` packets every 5 seconds to keep the socket alive; triggers automatic reconnection if consecutive heartbeats timeout.
   - **Receiver Channel** (`urn:x-cast:com.google.cast.receiver`): Launches the Default Media Receiver app ID (`CC1AD845`) and captures `sessionId` and `transportId`.
   - **Media Channel** (`urn:x-cast:com.google.cast.media`): Dispatches `LOAD` (with media metadata, MIME type, stream URL), `PLAY`, `PAUSE`, `SEEK`, `SET_VOLUME`, and processes `MEDIA_STATUS` broadcasts to maintain real-time position synchronization.

#### 4.2.3 End-to-End Cast & Streaming Sequence

```mermaid
sequenceDiagram
    autonumber
    participant UI as SwiftUI Cast Sheet / Coordinator
    participant Engine as Pure-Swift CastEngine (NWConnection)
    participant Bridge as Local HTTP Bridge (FlyingFox :8080)
    participant Receiver as Chromecast Device (Port 8009)

    UI->>Engine: startDiscovery()
    Engine->>Receiver: mDNS Probe (_googlecast._tcp)
    Receiver-->>Engine: TXT Record (Living Room TV, 192.168.1.105)
    Engine-->>UI: Update availableDevices List

    UI->>Engine: connect(device)
    Engine->>Receiver: TLS Handshake (Port 8009, Trust Self-Signed)
    Engine->>Receiver: [tp.connection] CONNECT (source: sender-0, dest: receiver-0)
    Engine->>Receiver: [receiver] LAUNCH (appId: "CC1AD845")
    Receiver-->>Engine: [receiver] RECEIVER_STATUS (sessionId, transportId: web-42)
    Engine->>Receiver: [tp.connection] CONNECT (dest: web-42)

    loop Heartbeat Loop (Every 5s)
        Engine->>Receiver: [tp.heartbeat] PING
        Receiver-->>Engine: [tp.heartbeat] PONG
    end

    UI->>Engine: castCurrentItem(mediaItem)
    Engine->>Bridge: Register local stream endpoint (/stream/movie.mp4)
    Bridge-->>Engine: Stream URL (http://192.168.1.50:8080/stream/movie.mp4)
    Engine->>Receiver: [media] LOAD (streamURL, contentType: "video/mp4", title)
    
    loop Dynamic Range 206 Streaming
        Receiver->>Bridge: GET /stream/movie.mp4 (Range: bytes=0-1048575)
        Bridge-->>Receiver: HTTP/1.1 206 Partial Content (Content-Range: 0-1048575/Total)
    end

    Receiver-->>Engine: [media] MEDIA_STATUS (currentTime, playerState: "PLAYING")
    Engine-->>UI: Sync Playback Position & Remote State
```

---

## 5. In-App Web Browser & Stream Sniffer
- Implemented via `WKWebView` with injected JavaScript hooks.
- Detects HTML5 `<video>`, `<audio>`, `.m3u8` (HLS), and MP4 streaming endpoints.
- Actions available: **"Play in App"**, **"Cast to TV"**, and **"Background Download"** (via `URLSessionConfiguration.background`).
