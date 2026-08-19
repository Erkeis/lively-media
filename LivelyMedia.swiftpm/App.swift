// [Intent] 100% Self-contained Pure-Swift Playgrounds executable app for iPad Air 5 with real-time AirPlay 2, NWListener HTTP 206 Range Streaming Server, and Cast V2 TLS socket engine
import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import WebKit
import UniformTypeIdentifiers
import Network
import Security

// MARK: - App Main Entrypoint
@main
struct LivelyMediaApp: App {
    @StateObject private var coordinator = PlaybackCoordinator.shared
    @StateObject private var castManager = CastManager.shared

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.allowAirPlay, .allowBluetooth, .defaultToSpeaker]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        // Automatically initialize local HTTP 206 server & mDNS scanner
        CastManager.shared.startServer()
        CastManager.shared.startDiscovery()
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(coordinator)
                .environmentObject(castManager)
                .preferredColorScheme(.dark)
        }
    }
}

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

// MARK: - Cast V2 Namespaces & Constants
enum CastV2Namespace {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let media = "urn:x-cast:com.google.cast.media"
}

enum CastV2AppId {
    static let defaultMediaReceiver = "CC1AD845"
}

// MARK: - Cast V2 Wire Framer (4-Byte Big-Endian Length Prefix)
enum CastV2Framer {
    // [Intent] Big-endian UInt32 length prefix ensures alignment-independent transmission over TLS sockets
    static func encodeFramedMessage(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(data)
        return framed
    }

    static func encodeFramedJSON<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        let payload = try encoder.encode(value)
        return encodeFramedMessage(payload)
    }

    // [Intent] Buffer slicing allows handling TCP fragmentation or multiple merged packets in a single read
    static func decodeFramedMessage(from buffer: inout Data) -> Data? {
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

// MARK: - Cast V2 Protocol Payload Models
struct CastConnectCommand: Codable, Sendable {
    let type: String
    init() { self.type = "CONNECT" }
}

struct CastCloseCommand: Codable, Sendable {
    let type: String
    init() { self.type = "CLOSE" }
}

struct CastPingCommand: Codable, Sendable {
    let type: String
    init() { self.type = "PING" }
}

struct CastPongCommand: Codable, Sendable {
    let type: String
    init() { self.type = "PONG" }
}

struct CastLaunchCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let appId: String
    init(requestId: Int, appId: String = CastV2AppId.defaultMediaReceiver) {
        self.type = "LAUNCH"
        self.requestId = requestId
        self.appId = appId
    }
}

struct CastMediaMetadata: Codable, Sendable {
    let metadataType: Int
    let title: String
    let subtitle: String?
    let artist: String?
    let albumName: String?

    init(metadataType: Int = 0, title: String, subtitle: String? = nil, artist: String? = nil, albumName: String? = nil) {
        self.metadataType = metadataType
        self.title = title
        self.subtitle = subtitle
        self.artist = artist
        self.albumName = albumName
    }
}

struct CastMediaInfo: Codable, Sendable {
    let contentId: String
    let streamType: String
    let contentType: String
    let metadata: CastMediaMetadata?
    let duration: Double?

    var title: String? {
        metadata?.title
    }

    var subtitle: String? {
        metadata?.subtitle
    }

    init(contentId: String, streamType: String = "BUFFERED", contentType: String, metadata: CastMediaMetadata? = nil, duration: Double? = nil) {
        self.contentId = contentId
        self.streamType = streamType
        self.contentType = contentType
        self.metadata = metadata
        self.duration = duration
    }
}

struct CastLoadCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let sessionId: String?
    let media: CastMediaInfo
    let autoplay: Bool
    let currentTime: Double

    init(requestId: Int, sessionId: String? = nil, media: CastMediaInfo, autoplay: Bool = true, currentTime: Double = 0.0) {
        self.type = "LOAD"
        self.requestId = requestId
        self.sessionId = sessionId
        self.media = media
        self.autoplay = autoplay
        self.currentTime = currentTime
    }
}

struct CastPlayCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let mediaSessionId: Int
    init(requestId: Int, mediaSessionId: Int) {
        self.type = "PLAY"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

struct CastPauseCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let mediaSessionId: Int
    init(requestId: Int, mediaSessionId: Int) {
        self.type = "PAUSE"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

struct CastMediaStopCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let mediaSessionId: Int
    init(requestId: Int, mediaSessionId: Int) {
        self.type = "STOP"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
    }
}

struct CastSeekCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let mediaSessionId: Int
    let currentTime: Double
    init(requestId: Int, mediaSessionId: Int, currentTime: Double) {
        self.type = "SEEK"
        self.requestId = requestId
        self.mediaSessionId = mediaSessionId
        self.currentTime = currentTime
    }
}

struct CastVolume: Codable, Sendable {
    let level: Float?
    let muted: Bool?
    init(level: Float? = nil, muted: Bool? = nil) {
        self.level = level
        self.muted = muted
    }
}

struct CastSetVolumeCommand: Codable, Sendable {
    let type: String
    let requestId: Int
    let volume: CastVolume
    init(requestId: Int, volume: CastVolume) {
        self.type = "SET_VOLUME"
        self.requestId = requestId
        self.volume = volume
    }
}

struct CastReceiverApplication: Codable, Sendable {
    let appId: String
    let displayName: String?
    let sessionId: String
    let statusText: String?
    let transportId: String
}

struct CastReceiverStatusItem: Codable, Sendable {
    let applications: [CastReceiverApplication]?
}

struct CastReceiverStatusResponse: Codable, Sendable {
    let type: String
    let requestId: Int?
    let status: CastReceiverStatusItem?
}

struct CastMediaStatusItem: Codable, Sendable {
    let mediaSessionId: Int
    let playerState: String
    let currentTime: Double?
    let media: CastMediaInfo?
}

struct CastMediaStatusResponse: Codable, Sendable {
    let type: String
    let requestId: Int?
    let status: [CastMediaStatusItem]
}

struct CastGenericResponse: Codable, Sendable {
    let type: String
    let requestId: Int?
}

// MARK: - Web Assets for Wi-Fi File Transfer UI
struct WebAssets {
    static let indexHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Obsidian Studio &bull; Wi-Fi Media Transfer</title>
        <style>
            :root {
                --bg: #0B0C0E;
                --surface: #14161A;
                --elevated: #1E2127;
                --border: #282C35;
                --amber: #E5A93C;
                --text-primary: #FFFFFF;
                --text-secondary: #9AA0AC;
                --text-muted: #636B78;
                --success: #30D158;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
            body { background-color: var(--bg); color: var(--text-primary); min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 40px 20px; }
            .container { width: 100%; max-width: 800px; }
            header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 30px; border-bottom: 1px solid var(--border); padding-bottom: 20px; }
            .brand { display: flex; align-items: center; gap: 12px; }
            .logo { width: 36px; height: 36px; background: var(--amber); border-radius: 8px; display: flex; align-items: center; justify-content: center; font-weight: bold; color: var(--bg); }
            h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
            .badge { font-size: 12px; background: var(--elevated); border: 1px solid var(--border); padding: 4px 10px; border-radius: 20px; color: var(--amber); }
            .drop-zone {
                background: var(--surface);
                border: 2px dashed var(--border);
                border-radius: 16px;
                padding: 50px 20px;
                text-align: center;
                cursor: pointer;
                transition: all 0.25s ease;
                margin-bottom: 30px;
            }
            .drop-zone:hover, .drop-zone.drag-over {
                border-color: var(--amber);
                background: var(--elevated);
                box-shadow: 0 0 20px rgba(229, 169, 60, 0.15);
            }
            .drop-icon { font-size: 40px; margin-bottom: 15px; color: var(--amber); }
            .drop-title { font-size: 18px; font-weight: 600; margin-bottom: 6px; }
            .drop-desc { font-size: 13px; color: var(--text-secondary); }
            .file-list-card {
                background: var(--surface);
                border: 1px solid var(--border);
                border-radius: 16px;
                padding: 24px;
            }
            .card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; font-weight: 600; font-size: 16px; }
            .file-table { width: 100%; border-collapse: collapse; text-align: left; font-size: 14px; }
            .file-table th { padding: 12px 8px; color: var(--text-muted); font-size: 12px; text-transform: uppercase; border-bottom: 1px solid var(--border); }
            .file-table td { padding: 14px 8px; border-bottom: 1px solid rgba(40, 44, 53, 0.5); }
            .file-name { font-weight: 500; }
            .file-size { color: var(--text-secondary); font-family: monospace; }
            .progress-bar-wrap { width: 100%; height: 6px; background: var(--elevated); border-radius: 3px; overflow: hidden; margin-top: 8px; display: none; }
            .progress-bar { width: 0%; height: 100%; background: var(--amber); transition: width 0.1s linear; }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <div class="brand">
                    <div class="logo">&bull;</div>
                    <div>
                        <h1>Obsidian Studio</h1>
                        <p style="font-size: 13px; color: var(--text-secondary)">Wi-Fi File Transfer & HTTP Bridge</p>
                    </div>
                </div>
                <div class="badge">Connected to iPad</div>
            </header>

            <div class="drop-zone" id="dropZone">
                <div class="drop-icon">&#8682;</div>
                <div class="drop-title">Drag & Drop Audio / Video Files Here</div>
                <div class="drop-desc">Supports MP4, MKV, FLAC, MP3, MOV, AAC, Subtitles (.srt, .ass)</div>
                <input type="file" id="fileInput" multiple style="display: none">
                <div class="progress-bar-wrap" id="progressWrap">
                    <div class="progress-bar" id="progressBar"></div>
                </div>
            </div>

            <div class="file-list-card">
                <div class="card-header">
                    <span>On-Device Media Files</span>
                    <button id="refreshBtn" style="background: var(--elevated); border: 1px solid var(--border); color: var(--text-primary); padding: 6px 12px; border-radius: 8px; cursor: pointer; font-size: 12px;">Refresh</button>
                </div>
                <table class="file-table">
                    <thead>
                        <tr>
                            <th>File Name</th>
                            <th>Size</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody id="fileTableBody">
                        <tr><td colspan="3" style="text-align: center; color: var(--text-muted); padding: 24px;">Loading files...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>

        <script>
            const dropZone = document.getElementById('dropZone');
            const fileInput = document.getElementById('fileInput');
            const progressWrap = document.getElementById('progressWrap');
            const progressBar = document.getElementById('progressBar');
            const fileTableBody = document.getElementById('fileTableBody');
            const refreshBtn = document.getElementById('refreshBtn');

            dropZone.addEventListener('click', () => fileInput.click());
            dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('drag-over'); });
            dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
            dropZone.addEventListener('drop', (e) => {
                e.preventDefault();
                dropZone.classList.remove('drag-over');
                if (e.dataTransfer.files.length > 0) uploadFiles(e.dataTransfer.files);
            });
            fileInput.addEventListener('change', () => { if (fileInput.files.length > 0) uploadFiles(fileInput.files); });
            refreshBtn.addEventListener('click', loadFiles);

            async function loadFiles() {
                try {
                    const res = await fetch('/api/files');
                    const files = await res.json();
                    if (!files || files.length === 0) {
                        fileTableBody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: var(--text-muted); padding: 24px;">No files on device yet. Upload above!</td></tr>';
                        return;
                    }
                    fileTableBody.innerHTML = files.map(f => `
                        <tr>
                            <td class="file-name">${f.name}</td>
                            <td class="file-size">${formatBytes(f.size)}</td>
                            <td style="color: var(--success); font-size: 12px;">Ready</td>
                        </tr>
                    `).join('');
                } catch (e) {
                    fileTableBody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: #FF453A; padding: 24px;">Failed to load files</td></tr>';
                }
            }

            async function uploadFiles(files) {
                progressWrap.style.display = 'block';
                for (let i = 0; i < files.length; i++) {
                    const file = files[i];
                    const formData = new FormData();
                    formData.append('file', file, file.name);

                    progressBar.style.width = '20%';
                    await fetch('/api/upload', { 
                        method: 'POST', 
                        headers: { 'X-File-Name': encodeURIComponent(file.name) },
                        body: formData 
                    });
                    progressBar.style.width = Math.round(((i + 1) / files.length) * 100) + '%';
                }
                setTimeout(() => {
                    progressWrap.style.display = 'none';
                    progressBar.style.width = '0%';
                    loadFiles();
                }, 500);
            }

            function formatBytes(bytes) {
                if (!bytes || bytes === 0) return '0 B';
                const k = 1024, sizes = ['B', 'KB', 'MB', 'GB'];
                const i = Math.floor(Math.log(bytes) / Math.log(k));
                return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
            }

            loadFiles();
        </script>
    </body>
    </html>
    """
}

// MARK: - Embedded Pure-Swift HTTP 206 Range Server (NWListener)
public final class EmbeddedRangeServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.livelymedia.rangeserver", qos: .userInitiated)
    private let lock = NSLock()
    private var _isRunning: Bool = false
    private var _port: UInt16 = 8080

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public var port: UInt16 {
        lock.withLock { _port }
    }

    public init() {}

    deinit {
        stop()
    }

    public func start(port: UInt16 = 8080) throws {
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let portEndpoint = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 8080)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: parameters, on: portEndpoint)

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.lock.withLock {
                    self._isRunning = true
                    self._port = port
                }
                print("[EmbeddedRangeServer] HTTP 206 server listening on port \(port)")
            case .failed(let error):
                self.lock.withLock { self._isRunning = false }
                print("[EmbeddedRangeServer] Listener failed: \(error)")
            case .cancelled:
                self.lock.withLock { self._isRunning = false }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.handleIncomingConnection(connection)
        }

        newListener.start(queue: queue)
        self.lock.withLock {
            self.listener = newListener
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        listener?.cancel()
        listener = nil
        _isRunning = false
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else {
                    connection.cancel()
                    return
                }

                if let data = data, !data.isEmpty {
                    buffer.append(data)

                    // Check if complete HTTP headers (\r\n\r\n) received
                    if let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
                        if let headerString = String(data: headerData, encoding: .utf8) {
                            let lines = headerString.components(separatedBy: "\r\n")
                            guard let requestLine = lines.first else {
                                connection.cancel()
                                return
                            }
                            let requestTokens = requestLine.components(separatedBy: " ")
                            guard requestTokens.count >= 2 else {
                                connection.cancel()
                                return
                            }
                            let method = requestTokens[0].uppercased()
                            let rawPath = requestTokens[1]

                            var headers: [String: String] = [:]
                            for line in lines.dropFirst() {
                                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                                if parts.count == 2 {
                                    let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                                    let val = parts[1].trimmingCharacters(in: .whitespaces)
                                    headers[key] = val
                                }
                            }

                            let bodyData = buffer.subdata(in: headerRange.upperBound..<buffer.count)
                            let contentLength = Int(headers["content-length"] ?? "0") ?? 0

                            if method == "POST" && bodyData.count < contentLength {
                                // Needs more body bytes for file upload
                                readMore()
                                return
                            }

                            self.processRequest(
                                method: method,
                                rawPath: rawPath,
                                headers: headers,
                                body: bodyData,
                                connection: connection
                            )
                            return
                        }
                    }
                }

                if error != nil || isComplete {
                    connection.cancel()
                    return
                }

                readMore()
            }
        }

        readMore()
    }

    private func processRequest(
        method: String,
        rawPath: String,
        headers: [String: String],
        body: Data,
        connection: NWConnection
    ) {
        let cleanPath = rawPath.components(separatedBy: "?").first ?? rawPath

        // Route 1: Web UI Root
        if method == "GET" && (cleanPath == "/" || cleanPath.isEmpty) {
            let htmlData = Data(WebAssets.indexHTML.utf8)
            sendResponse(
                status: "200 OK",
                headers: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Length": "\(htmlData.count)",
                    "Cache-Control": "no-cache"
                ],
                body: htmlData,
                on: connection
            )
            return
        }

        // Route 2: File Listing API
        if method == "GET" && cleanPath == "/api/files" {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileManager = FileManager.default
            let files = (try? fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey])) ?? []

            var items: [[String: Any]] = []
            for url in files {
                guard !url.lastPathComponent.hasPrefix(".") else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                items.append(["name": url.lastPathComponent, "size": size])
            }

            let jsonData = (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8)
            sendResponse(
                status: "200 OK",
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": "\(jsonData.count)",
                    "Access-Control-Allow-Origin": "*"
                ],
                body: jsonData,
                on: connection
            )
            return
        }

        // Route 3: Upload API
        if method == "POST" && cleanPath == "/api/upload" {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            var targetFileName = "upload_\(UUID().uuidString.prefix(8)).bin"
            var fileData = body

            if let customName = headers["x-file-name"]?.removingPercentEncoding, !customName.isEmpty {
                targetFileName = customName
            }

            // Extract file data from multipart if present
            if let multipart = extractMultipartFile(body: body, contentType: headers["content-type"]) {
                targetFileName = multipart.fileName
                fileData = multipart.data
            }

            let destinationURL = docs.appendingPathComponent(targetFileName)
            do {
                try fileData.write(to: destinationURL, options: .atomic)
                Task { @MainActor in
                    let isVideo = ["mp4", "mov", "mkv", "avi", "m4v"].contains(destinationURL.pathExtension.lowercased())
                    let newItem = MediaItem(
                        title: destinationURL.deletingPathExtension().lastPathComponent,
                        filePath: destinationURL.path,
                        fileName: destinationURL.lastPathComponent,
                        fileSize: Int64(fileData.count),
                        duration: 0.0,
                        mediaType: isVideo ? .video : .audio,
                        containerFormat: destinationURL.pathExtension
                    )
                    StorageManager.shared.addItem(newItem)
                }

                let successJSON = Data("{\"status\":\"success\"}".utf8)
                sendResponse(
                    status: "200 OK",
                    headers: [
                        "Content-Type": "application/json",
                        "Content-Length": "\(successJSON.count)",
                        "Access-Control-Allow-Origin": "*"
                    ],
                    body: successJSON,
                    on: connection
                )
            } catch {
                let errJSON = Data("{\"error\":\"\(error.localizedDescription)\"}".utf8)
                sendResponse(
                    status: "500 Internal Server Error",
                    headers: ["Content-Type": "application/json", "Content-Length": "\(errJSON.count)"],
                    body: errJSON,
                    on: connection
                )
            }
            return
        }

        // Route 4: HTTP Range 206 Streaming for Chromecast & Remote Players
        if method == "GET" && cleanPath.hasPrefix("/stream") {
            handleRangeStreamRequest(cleanPath: cleanPath, headers: headers, connection: connection)
            return
        }

        // 404 Fallback
        sendResponse(status: "404 Not Found", headers: ["Content-Length": "0"], body: Data(), on: connection)
    }

    private func handleRangeStreamRequest(cleanPath: String, headers: [String: String], connection: NWConnection) {
        // [Intent] Resolves file, parses "Range: bytes=start-end", reads file slice via FileHandle, and returns 206 Partial Content
        var subpath = cleanPath.replacingOccurrences(of: "/stream/", with: "")
        if subpath.hasPrefix("/stream") {
            subpath = subpath.replacingOccurrences(of: "/stream", with: "")
        }
        if subpath.hasPrefix("/") {
            subpath = String(subpath.dropFirst())
        }

        let decodedName = subpath.removingPercentEncoding ?? subpath
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var fileURL = docs.appendingPathComponent(decodedName)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // [Intent] Check filesystem and JSON library directly to avoid crossing @MainActor boundary from background server
            let libraryJSONURL = docs.appendingPathComponent("lively_library.json")
            if let data = try? Data(contentsOf: libraryJSONURL),
               let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
                if let matched = decoded.first(where: { $0.fileName == decodedName || $0.filePath.hasSuffix(decodedName) }) {
                    if FileManager.default.fileExists(atPath: matched.filePath) {
                        fileURL = URL(fileURLWithPath: matched.filePath)
                    }
                }
            }
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) && FileManager.default.fileExists(atPath: decodedName) {
            fileURL = URL(fileURLWithPath: decodedName)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sendResponse(status: "404 Not Found", headers: ["Content-Length": "0"], body: Data(), on: connection)
            return
        }

        let fileSize: UInt64
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = (attr[.size] as? UInt64) ?? 0
        } catch {
            fileSize = 0
        }

        let contentType = mimeType(for: fileURL.pathExtension)

        if let rangeHeader = headers["range"], rangeHeader.hasPrefix("bytes=") {
            let rangeSpec = rangeHeader.replacingOccurrences(of: "bytes=", with: "").trimmingCharacters(in: .whitespaces)
            let parts = rangeSpec.split(separator: "-", omittingEmptySubsequences: false)

            var start: UInt64 = 0
            var end: UInt64 = fileSize > 0 ? (fileSize - 1) : 0

            if parts.count == 2 {
                if !parts[0].isEmpty {
                    start = UInt64(parts[0]) ?? 0
                }
                if !parts[1].isEmpty {
                    end = UInt64(parts[1]) ?? (fileSize > 0 ? (fileSize - 1) : 0)
                } else {
                    end = fileSize > 0 ? (fileSize - 1) : 0
                }
            } else if parts.count == 1 && !parts[0].isEmpty {
                start = UInt64(parts[0]) ?? 0
                end = fileSize > 0 ? (fileSize - 1) : 0
            }

            if fileSize > 0 {
                start = min(start, fileSize - 1)
                end = min(end, fileSize - 1)
            }
            if end < start { end = start }
            let length = (end - start) + 1

            guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
                sendResponse(status: "500 Internal Server Error", headers: [:], body: Data(), on: connection)
                return
            }
            defer { try? fileHandle.close() }

            try? fileHandle.seek(toOffset: start)
            let chunkData = fileHandle.readData(ofLength: Int(length))

            let respHeaders: [String: String] = [
                "Content-Type": contentType,
                "Content-Range": "bytes \(start)-\(end)/\(fileSize)",
                "Content-Length": "\(chunkData.count)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*",
                "Connection": "close"
            ]

            sendResponse(status: "206 Partial Content", headers: respHeaders, body: chunkData, on: connection)
        } else {
            guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
                sendResponse(status: "500 Internal Server Error", headers: [:], body: Data(), on: connection)
                return
            }
            defer { try? fileHandle.close() }

            let fullData = fileHandle.readDataToEndOfFile()
            let respHeaders: [String: String] = [
                "Content-Type": contentType,
                "Content-Length": "\(fullData.count)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*",
                "Connection": "close"
            ]
            sendResponse(status: "200 OK", headers: respHeaders, body: fullData, on: connection)
        }
    }

    private func extractMultipartFile(body: Data, contentType: String?) -> (fileName: String, data: Data)? {
        guard let contentType = contentType,
              let boundaryRange = contentType.range(of: "boundary=") else {
            return nil
        }
        let boundary = String(contentType[boundaryRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let boundaryData = Data(("--" + boundary).utf8)

        guard let firstBoundary = body.range(of: boundaryData) else { return nil }
        let restOfBody = body.subdata(in: firstBoundary.upperBound..<body.count)

        guard let headerEndRange = restOfBody.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerBytes = restOfBody.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerBytes, encoding: .utf8) else { return nil }

        var filename = "uploaded_\(UUID().uuidString.prefix(8)).bin"
        if let fnRange = headerString.range(of: "filename=\"") {
            let fnSubstring = headerString[fnRange.upperBound...]
            if let fnEnd = fnSubstring.firstIndex(of: "\"") {
                filename = String(fnSubstring[..<fnEnd])
            }
        }

        let contentStart = headerEndRange.upperBound
        let remainingData = restOfBody.subdata(in: contentStart..<restOfBody.count)
        let nextBoundary = Data(("\r\n--" + boundary).utf8)

        if let endRange = remainingData.range(of: nextBoundary) {
            let fileData = remainingData.subdata(in: 0..<endRange.lowerBound)
            return (filename, fileData)
        } else {
            return (filename, remainingData)
        }
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "mp4", "m4v", "mov": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "flac": return "audio/flac"
        case "aac", "m4a": return "audio/aac"
        case "wav": return "audio/wav"
        case "m3u8": return "application/x-mpegURL"
        case "json": return "application/json"
        case "html", "htm": return "text/html"
        default: return "application/octet-stream"
        }
    }

    private func sendResponse(
        status: String,
        headers: [String: String],
        body: Data,
        on connection: NWConnection
    ) {
        var headerStr = "HTTP/1.1 \(status)\r\n"
        for (k, v) in headers {
            headerStr += "\(k): \(v)\r\n"
        }
        if headers["Connection"] == nil {
            headerStr += "Connection: close\r\n"
        }
        headerStr += "\r\n"

        var responseData = Data(headerStr.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Local Wi-Fi & Cast Manager (Multi-Protocol Discovery & TLS Socket Engine)
@MainActor
final class CastManager: ObservableObject {
    static let shared = CastManager()

    @Published var localIPAddress: String = "Detecting Wi-Fi..."
    @Published var isCastModalPresented: Bool = false
    @Published var isCastingActive: Bool = false
    @Published var activeCastDevice: CastDevice?
    @Published var connectionState: CastConnectionState = .disconnected
    @Published var discoveredChromecasts: [CastDevice] = []
    @Published var currentCastMediaStatus: String = "IDLE"
    @Published var castPlaybackPosition: Double = 0.0
    @Published var castDuration: Double = 0.0
    @Published var isServerRunning: Bool = false
    @Published var isScanning: Bool = false
    @Published var manualIPInput: String = ""
    @Published var scanStatusMessage: String = ""

    public let serverPort: UInt16 = 8080
    private let rangeServer = EmbeddedRangeServer()

    // Discovery & Socket
    private var browser: NWBrowser?
    private let discoveryQueue = DispatchQueue(label: "com.livelymedia.cast.discovery", qos: .userInitiated)
    private var connection: NWConnection?
    private let socketQueue = DispatchQueue(label: "com.livelymedia.cast.socket", qos: .userInitiated)
    private var heartbeatTask: Task<Void, Never>?
    private var receiveBuffer = Data()
    private var requestIdCounter: Int = 1
    private var currentMediaSessionId: Int?
    private var currentSessionId: String?

    init() {
        refreshNetworkState()
        // [Intent] Start with empty list to ensure only real on-network devices are listed
        self.discoveredChromecasts = []
    }

    deinit {
        heartbeatTask?.cancel()
        browser?.cancel()
        connection?.cancel()
        rangeServer.stop()
    }

    func startServer() {
        refreshNetworkState()
        do {
            try rangeServer.start(port: serverPort)
            self.isServerRunning = rangeServer.isRunning
        } catch {
            print("[CastManager] Range server start failure: \(error)")
            self.isServerRunning = false
        }
    }

    func stopServer() {
        rangeServer.stop()
        self.isServerRunning = false
    }

    func refreshNetworkState() {
        if let ip = getWiFiIPAddress() {
            self.localIPAddress = ip
        } else {
            self.localIPAddress = "127.0.0.1 (Local Only)"
        }
    }

    // MARK: - Multi-Protocol Discovery (Subnet Eureka Probe + Bonjour mDNS)
    func startDiscovery() {
        refreshNetworkState()
        self.isScanning = true
        self.scanStatusMessage = "Scanning Wi-Fi network..."

        // 1. Native Bonjour mDNS Browser
        startBonjourDiscovery()

        // 2. Active Subnet Eureka / DIAL HTTP Probe (Port 8008)
        scanSubnetEureka()
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        self.isScanning = false
    }

    private func startBonjourDiscovery() {
        browser?.cancel()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_googlecast._tcp", domain: "local.")
        let parameters = NWParameters()
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleDiscoveredResults(results)
            }
        }

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .failed = state {
                    print("[CastManager] Bonjour discovery failed, relying on subnet scan")
                }
            }
        }

        newBrowser.start(queue: discoveryQueue)
        self.browser = newBrowser
    }

    private func scanSubnetEureka() {
        // [Intent] Google Cast devices run HTTP REST server on port 8008 with /setup/eureka_info
        // Scanning active /24 subnet discovers devices even when Wi-Fi AP isolation blocks mDNS multicast
        guard let ip = getWiFiIPAddress(), !ip.hasPrefix("127.0.") else {
            self.isScanning = false
            return
        }

        let components = ip.split(separator: ".")
        guard components.count == 4 else {
            self.isScanning = false
            return
        }
        let subnetPrefix = "\(components[0]).\(components[1]).\(components[2])."
        let myLastOctet = Int(components[3]) ?? 0

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 1.5
        let session = URLSession(configuration: config)

        Task {
            await withTaskGroup(of: CastDevice?.self) { group in
                for i in 1...254 {
                    if i == myLastOctet { continue }
                    let targetIP = "\(subnetPrefix)\(i)"
                    group.addTask {
                        guard let url = URL(string: "http://\(targetIP):8008/setup/eureka_info") else { return nil }
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 1.5
                        do {
                            let (data, response) = try await session.data(for: request)
                            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                let name = (json["name"] as? String) ?? "Google Cast (\(targetIP))"
                                let model = (json["model_name"] as? String) ?? "Chromecast"
                                let bssid = (json["bssid"] as? String) ?? "cast_\(targetIP.replacingOccurrences(of: ".", with: "_"))"
                                return CastDevice(
                                    id: bssid,
                                    name: name,
                                    type: .chromecast,
                                    ipAddress: targetIP,
                                    port: 8009,
                                    modelName: model,
                                    capabilities: ["video_out", "audio_out"]
                                )
                            }
                        } catch {
                            return nil
                        }
                        return nil
                    }
                }

                for await found in group {
                    if let device = found {
                        Task { @MainActor in
                            if !self.discoveredChromecasts.contains(where: { $0.ipAddress == device.ipAddress }) {
                                self.discoveredChromecasts.append(device)
                                print("[CastManager] Discovered Chromecast via Subnet Eureka: \(device.name) at \(device.ipAddress ?? "")")
                            }
                        }
                    }
                }
            }

            Task { @MainActor in
                self.isScanning = false
                self.scanStatusMessage = self.discoveredChromecasts.isEmpty ? "No devices found on subnet. Try entering IP below." : "Found \(self.discoveredChromecasts.count) device(s)"
            }
        }
    }

    private func handleDiscoveredResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            var name = "Google Cast Device"
            var modelName: String? = nil
            var deviceId = UUID().uuidString
            var capabilities: [String] = []
            var ipAddress: String? = nil
            var port: UInt16 = 8009

            switch result.endpoint {
            case .service(let serviceName, _, _, _):
                name = serviceName
                deviceId = serviceName
            case .hostPort(let host, let hostPort):
                name = "\(host)"
                deviceId = "\(host)"
                port = hostPort.rawValue
                switch host {
                case .ipv4(let ip):
                    ipAddress = "\(ip)"
                case .ipv6(let ip):
                    ipAddress = "\(ip)"
                case .name(let hostName, _):
                    ipAddress = hostName
                @unknown default:
                    break
                }
            case .unix(let path):
                name = "Unix Socket"
                deviceId = path
            case .url(let url):
                name = url.absoluteString
                deviceId = url.absoluteString
            case .opaque:
                name = "Opaque Endpoint"
                deviceId = UUID().uuidString
            @unknown default:
                break
            }

            if case .bonjour(let txtRecord) = result.metadata {
                if let fn = txtRecord.dictionary["fn"] {
                    name = fn
                }
                if let id = txtRecord.dictionary["id"] {
                    deviceId = id
                }
                if let md = txtRecord.dictionary["md"] {
                    modelName = md
                }
                if let ca = txtRecord.dictionary["ca"] {
                    capabilities.append(ca)
                }
            }

            let device = CastDevice(
                id: deviceId,
                name: name,
                type: .chromecast,
                ipAddress: ipAddress,
                port: port,
                modelName: modelName,
                capabilities: capabilities
            )

            if !self.discoveredChromecasts.contains(where: { $0.id == device.id || ($0.ipAddress != nil && $0.ipAddress == device.ipAddress) }) {
                self.discoveredChromecasts.append(device)
            }
        }
    }

    func connectDirectly(ip: String, port: UInt16 = 8009) async {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Probe Eureka info to resolve friendly name if possible
        var deviceName = "Google Cast (\(trimmed))"
        var modelName = "Chromecast"
        if let url = URL(string: "http://\(trimmed):8008/setup/eureka_info") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.0
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let name = json["name"] as? String { deviceName = name }
                if let model = json["model_name"] as? String { modelName = model }
            }
        }

        let device = CastDevice(
            id: "manual_\(trimmed)",
            name: deviceName,
            type: .chromecast,
            ipAddress: trimmed,
            port: port,
            modelName: modelName,
            capabilities: ["video_out", "audio_out"]
        )

        if !self.discoveredChromecasts.contains(where: { $0.ipAddress == trimmed }) {
            self.discoveredChromecasts.insert(device, at: 0)
        }

        await connect(to: device)
    }

    func getStreamBridgeURL(for item: MediaItem) -> String {
        let encoded = item.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.fileName
        let hostIP = localIPAddress.components(separatedBy: " ").first ?? "127.0.0.1"
        return "http://\(hostIP):\(serverPort)/stream/\(encoded)"
    }

    // MARK: - Cast V2 Socket Connect & Controls
    func connect(to device: CastDevice) async {
        self.connectionState = .connecting
        self.activeCastDevice = device

        guard let ip = device.ipAddress, !ip.isEmpty else {
            self.connectionState = .failed("Missing IP address for Cast device")
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: device.port) ?? NWEndpoint.Port(integerLiteral: 8009)
        )

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { (_, _, completion) in
                // [Intent] Accept Chromecast self-signed certificates for local device streaming
                completion(true)
            },
            DispatchQueue.global(qos: .userInitiated)
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let nwConn = NWConnection(to: endpoint, using: parameters)
        self.connection = nwConn

        nwConn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectionState = .connected(deviceName: device.name)
                    self.isCastingActive = true
                    self.startReceiveLoop(nwConn)

                    // 1. Handshake CONNECT
                    try? await self.sendFramedJSON(CastConnectCommand())

                    // 2. Launch Default Media Receiver
                    let launch = CastLaunchCommand(requestId: self.nextRequestId(), appId: CastV2AppId.defaultMediaReceiver)
                    try? await self.sendFramedJSON(launch)

                    // 3. Start Heartbeat loop
                    self.startHeartbeatLoop()

                    // 4. Stream current media item
                    if let item = PlaybackCoordinator.shared.currentItem {
                        await self.loadMedia(item: item)
                    }

                case .failed(let error):
                    self.connectionState = .failed(error.localizedDescription)
                    self.isCastingActive = false
                case .cancelled:
                    self.connectionState = .disconnected
                    self.isCastingActive = false
                default:
                    break
                }
            }
        }

        nwConn.start(queue: socketQueue)
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        if let _ = connection {
            Task {
                try? await self.sendFramedJSON(CastCloseCommand())
            }
        }
        connection?.cancel()
        connection = nil

        self.activeCastDevice = nil
        self.currentSessionId = nil
        self.currentMediaSessionId = nil
        self.connectionState = .disconnected
        self.isCastingActive = false
        self.receiveBuffer.removeAll()
    }

    func loadMedia(item: MediaItem) async {
        let streamURLString = getStreamBridgeURL(for: item)
        guard let streamURL = URL(string: streamURLString) else { return }

        // [Intent] Pause local iPad AVPlayer when routing media to remote Cast receiver
        PlaybackCoordinator.shared.player.pause()
        PlaybackCoordinator.shared.isPlaying = false

        let contentType: String
        switch item.containerFormat.lowercased() {
        case "mp4", "m4v", "mov": contentType = "video/mp4"
        case "mkv", "webm": contentType = "video/webm"
        case "mp3": contentType = "audio/mpeg"
        case "flac": contentType = "audio/flac"
        case "aac", "m4a": contentType = "audio/aac"
        default: contentType = item.mediaType == .video ? "video/mp4" : "audio/mpeg"
        }

        let mediaMetadata = CastMediaMetadata(
            metadataType: 0,
            title: item.title,
            subtitle: item.artist ?? item.album,
            artist: item.artist,
            albumName: item.album
        )
        let mediaInfo = CastMediaInfo(
            contentId: streamURL.absoluteString,
            streamType: "BUFFERED",
            contentType: contentType,
            metadata: mediaMetadata,
            duration: item.duration
        )
        let loadCmd = CastLoadCommand(
            requestId: nextRequestId(),
            sessionId: currentSessionId,
            media: mediaInfo,
            autoplay: true,
            currentTime: item.playbackPosition
        )
        try? await sendFramedJSON(loadCmd)
    }

    func play() async {
        guard let mediaSessionId = currentMediaSessionId else { return }
        let cmd = CastPlayCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try? await sendFramedJSON(cmd)
    }

    func pause() async {
        guard let mediaSessionId = currentMediaSessionId else { return }
        let cmd = CastPauseCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try? await sendFramedJSON(cmd)
    }

    func seek(to seconds: Double) async {
        guard let mediaSessionId = currentMediaSessionId else { return }
        let cmd = CastSeekCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId, currentTime: seconds)
        try? await sendFramedJSON(cmd)
    }

    func stop() async {
        guard let mediaSessionId = currentMediaSessionId else { return }
        let cmd = CastMediaStopCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try? await sendFramedJSON(cmd)
    }

    private func startHeartbeatLoop() {
        // [Intent] Periodically send PING packets every 5 seconds to keep Cast receiver TLS connection alive
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                let isConnected: Bool = await self.isCastingActive
                guard isConnected else { break }
                try? await self.sendFramedJSON(CastPingCommand())
            }
        }
    }

    private func sendFramedJSON<T: Encodable>(_ value: T) async throws {
        guard let conn = connection else { return }
        let data = try CastV2Framer.encodeFramedJSON(value)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func startReceiveLoop(_ nwConn: NWConnection) {
        nwConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let data = content, !data.isEmpty {
                    self.processIncomingData(data)
                }
                if error != nil || isComplete {
                    self.disconnect()
                    return
                }
                self.startReceiveLoop(nwConn)
            }
        }
    }

    private func processIncomingData(_ data: Data) {
        receiveBuffer.append(data)
        while true {
            guard let packet = CastV2Framer.decodeFramedMessage(from: &receiveBuffer) else { break }
            processPacketPayload(packet)
        }
    }

    private func processPacketPayload(_ payload: Data) {
        let decoder = JSONDecoder()

        if let generic = try? decoder.decode(CastGenericResponse.self, from: payload) {
            if generic.type == "PING" {
                Task { try? await self.sendFramedJSON(CastPongCommand()) }
            } else if generic.type == "CLOSE" {
                self.disconnect()
            }
        }

        if let receiverStatus = try? decoder.decode(CastReceiverStatusResponse.self, from: payload) {
            if let apps = receiverStatus.status?.applications {
                if let mediaApp = apps.first(where: { $0.appId == CastV2AppId.defaultMediaReceiver }) ?? apps.first {
                    self.currentSessionId = mediaApp.sessionId
                }
            }
        }

        if let mediaStatus = try? decoder.decode(CastMediaStatusResponse.self, from: payload) {
            if let first = mediaStatus.status.first {
                self.currentMediaSessionId = first.mediaSessionId
                self.currentCastMediaStatus = first.playerState
                if let ct = first.currentTime {
                    self.castPlaybackPosition = ct
                }
                if let dur = first.media?.duration {
                    self.castDuration = dur
                }
            }
        }
    }

    private func nextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
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
                        if name == "en0" || name == "pdp_ip0" || name == "bridge0" || name == "wlan0" {
                            address = String(cString: hostname)
                            break
                        } else if address == nil && !name.hasPrefix("lo") {
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

enum CastTargetType: String, Sendable, Codable {
    case localDevice, airPlay, chromecast
}

enum CastConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(deviceName: String)
    case failed(String)
}

struct CastDevice: Identifiable, Sendable, Hashable, Codable {
    var id: String
    var name: String
    var type: CastTargetType
    var ipAddress: String?
    var port: UInt16
    var modelName: String?
    var capabilities: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        type: CastTargetType = .chromecast,
        ipAddress: String? = nil,
        port: UInt16 = 8009,
        modelName: String? = nil,
        capabilities: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.ipAddress = ipAddress
        self.port = port
        self.modelName = modelName
        self.capabilities = capabilities
    }
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
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let item = items[idx]
            if !item.filePath.hasPrefix("http://") && !item.filePath.hasPrefix("https://") {
                try? FileManager.default.removeItem(atPath: item.filePath)
            }
            items.remove(at: idx)
            saveItems()
        }
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
            if let parsed = URL(string: item.filePath) {
                url = parsed
            } else if let encoded = item.filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let parsed = URL(string: encoded) {
                url = parsed
            } else {
                url = URL(fileURLWithPath: item.filePath)
            }
        } else {
            url = URL(fileURLWithPath: item.filePath)
        }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true

        statusObserver?.invalidate()
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] pItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if pItem.status == .readyToPlay {
                    self.isBuffering = false
                    let dur = CMTimeGetSeconds(pItem.duration)
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                } else if pItem.status == .failed {
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
    static let studioGreen = Color(red: 48/255, green: 209/255, blue: 88/255)
}

// MARK: - Main UI View
struct MainContentView: View {
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @EnvironmentObject var castManager: CastManager
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

                                // Interactive Cast & Network Button
                                Button(action: { castManager.isCastModalPresented = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: castManager.isCastingActive ? "tv.and.mediabox.fill" : "tv.badge.wifi")
                                            .font(.system(size: 14))
                                        Text(castManager.isCastingActive ? "Casting Active" : "Cast & AirPlay")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundColor(castManager.isCastingActive ? .studioGreen : .studioAmber)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.obsidianElevated)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(castManager.isCastingActive ? Color.studioGreen : Color.obsidianBorder, lineWidth: 0.5)
                                    )
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

                    #if os(iOS)
                    AirPlayRoutePickerButton(isVideo: false, size: 32)
                        .frame(width: 32, height: 32)
                    #endif

                    Button(action: { castManager.isCastModalPresented = true }) {
                        Image(systemName: castManager.isCastingActive ? "tv.and.mediabox.fill" : "tv.badge.wifi")
                            .font(.system(size: 18))
                            .foregroundColor(castManager.isCastingActive ? .studioGreen : .studioAmber)
                    }

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
                        Image(systemName: castManager.isCastingActive ? "tv.and.mediabox.fill" : "tv.badge.wifi")
                            .font(.system(size: 16))
                            .foregroundColor(castManager.isCastingActive ? .studioGreen : .studioAmber)
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

                        // Section 2: Active Remote Cast Controller (if connected)
                        if castManager.isCastingActive, let device = castManager.activeCastDevice {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "tv.and.mediabox.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.studioGreen)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Active Remote Cast Session")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("\(device.name) • \(castManager.currentCastMediaStatus)")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.studioGreen)
                                    }
                                    Spacer()
                                    Button("Disconnect") {
                                        castManager.disconnect()
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(8)
                                }

                                if let item = coordinator.currentItem {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 24) {
                                    Button(action: {
                                        Task { await castManager.seek(to: max(0, castManager.castPlaybackPosition - 10)) }
                                    }) {
                                        Image(systemName: "gobackward.10")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    }

                                    Button(action: {
                                        Task {
                                            if castManager.currentCastMediaStatus == "PLAYING" {
                                                await castManager.pause()
                                            } else {
                                                await castManager.play()
                                            }
                                        }
                                    }) {
                                        Image(systemName: castManager.currentCastMediaStatus == "PLAYING" ? "pause.fill" : "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.obsidianBackground)
                                            .frame(width: 46, height: 46)
                                            .background(Color.studioGreen)
                                            .clipShape(Circle())
                                    }

                                    Button(action: {
                                        Task { await castManager.seek(to: castManager.castPlaybackPosition + 10) }
                                    }) {
                                        Image(systemName: "goforward.10")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .padding(18)
                            .background(Color.obsidianSurface)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.studioGreen.opacity(0.6), lineWidth: 1))
                        }

                        // Section 3: Chromecast & Local HTTP 206 Streaming Bridge
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "tv.badge.wifi")
                                    .font(.system(size: 22))
                                    .foregroundColor(.studioAmber)
                                Text("Chromecast Local HTTP Bridge")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(castManager.isServerRunning ? "SERVER ACTIVE" : "STOPPED")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(castManager.isServerRunning ? .studioGreen : .studioSlate)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.obsidianElevated)
                                    .cornerRadius(6)
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

                            HStack {
                                Text("Discovered Google Cast Devices on Wi-Fi:")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                if castManager.isScanning {
                                    ProgressView()
                                        .tint(.studioAmber)
                                        .scaleEffect(0.8)
                                } else {
                                    Button(action: { castManager.startDiscovery() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Scan Wi-Fi")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(.studioAmber)
                                    }
                                }
                            }

                            if castManager.isScanning && castManager.discoveredChromecasts.isEmpty {
                                HStack(spacing: 12) {
                                    ProgressView().tint(.studioAmber)
                                    Text("Scanning local Wi-Fi and subnet for Chromecast & Smart TVs...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.studioSlate)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                            } else if castManager.discoveredChromecasts.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("No Google Cast devices found automatically on this Wi-Fi network.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.studioSlate)
                                    Text("Ensure iPad and TV are on the same Wi-Fi, or enter your TV's IP below:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.studioAmber)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                            }

                            ForEach(castManager.discoveredChromecasts) { device in
                                HStack {
                                    Image(systemName: "tv.fill")
                                        .foregroundColor(.studioAmber)
                                        .font(.system(size: 18))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                        HStack(spacing: 6) {
                                            if let model = device.modelName {
                                                Text(model)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.studioAmber)
                                                Text("•")
                                                    .foregroundColor(.obsidianBorder)
                                            }
                                            if let ip = device.ipAddress {
                                                Text("\(ip):\(device.port)")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.studioSlate)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Button("Cast") {
                                        Task {
                                            await castManager.connect(to: device)
                                        }
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.studioAmber)
                                    .foregroundColor(.obsidianBackground)
                                    .cornerRadius(8)
                                }
                                .padding(12)
                                .background(Color.obsidianElevated)
                                .cornerRadius(10)
                            }

                            Divider().background(Color.obsidianBorder)

                            // Manual Direct IP Connection Row
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Direct TV IP Connection:")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                HStack(spacing: 8) {
                                    TextField("e.g. 192.168.1.55", text: $castManager.manualIPInput)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .padding(10)
                                        .background(Color.obsidianElevated)
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .font(.system(size: 13, design: .monospaced))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.obsidianBorder, lineWidth: 0.5))

                                    Button("Connect & Cast") {
                                        Task {
                                            await castManager.connectDirectly(ip: castManager.manualIPInput)
                                        }
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.studioAmber)
                                    .foregroundColor(.obsidianBackground)
                                    .cornerRadius(8)
                                }
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
    @EnvironmentObject var coordinator: PlaybackCoordinator
    @StateObject private var storage = StorageManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi")
                            .font(.system(size: 50))
                            .foregroundColor(.studioAmber)
                        Text("Wi-Fi File Transfer & HTTP Bridge")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("Connect from your PC/Mac browser to drag & drop files directly into this iPad:")
                            .font(.system(size: 13))
                            .foregroundColor(.studioSlate)
                            .multilineTextAlignment(.center)

                        Text("http://\(castManager.localIPAddress.components(separatedBy: " ").first ?? "127.0.0.1"):\(castManager.serverPort)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.studioAmber)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.obsidianElevated)
                            .cornerRadius(10)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(castManager.isServerRunning ? Color.studioGreen : Color.red)
                                .frame(width: 8, height: 8)
                            Text(castManager.isServerRunning ? "Server Running on Port \(castManager.serverPort)" : "Server Stopped")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.studioSlate)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))

                    // Local Storage File Manager
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("On-Device Media Files", systemImage: "internaldrive")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(storage.items.count) items")
                                .font(.system(size: 12))
                                .foregroundColor(.studioSlate)
                        }

                        ForEach(storage.items) { item in
                            HStack {
                                Image(systemName: item.mediaType == .video ? "film" : "music.note")
                                    .foregroundColor(.studioAmber)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(item.fileName)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.studioSlate)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(action: { coordinator.playItem(item) }) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.studioAmber)
                                        .padding(8)
                                        .background(Color.obsidianElevated)
                                        .clipShape(Circle())
                                }

                                Button(action: { storage.deleteItem(id: item.id) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(8)
                                        .background(Color.obsidianElevated)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(10)
                            .background(Color.obsidianElevated)
                            .cornerRadius(10)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.obsidianSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.obsidianBorder, lineWidth: 0.5))

                    // Linux Test Server Fixtures
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
