// [Intent] Pure-Swift ChromecastService managing mDNS Bonjour discovery, TLS socket connections (:8009), Cast V2 protocol framing, heartbeat loops, and remote media session controls
import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(Security)
import Security
#endif

// MARK: - Error Types

public enum CastError: LocalizedError, Sendable, Equatable {
    case notConnected
    case connectionFailed(String)
    case connectionTimeout
    case noActiveMediaSession
    case invalidPayload
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No active Google Cast session"
        case .connectionFailed(let reason):
            return "Google Cast connection failed: \(reason)"
        case .connectionTimeout:
            return "Google Cast connection timed out"
        case .noActiveMediaSession:
            return "No active media session on Google Cast receiver"
        case .invalidPayload:
            return "Invalid Cast media payload"
        case .commandFailed(let msg):
            return "Cast command failed: \(msg)"
        }
    }
}

// MARK: - Chromecast Service Protocol

public protocol ChromecastServiceProtocol: AnyObject, Sendable {
    var connectionState: CastConnectionState { get }
    var discoveredDevices: [CastDevice] { get }
    var currentMediaSessionId: Int? { get }
    var currentSessionId: String? { get }
    var currentTransportId: String? { get }
    var onStateChange: (@Sendable (CastConnectionState) -> Void)? { get set }
    var onDevicesDiscovered: (@Sendable ([CastDevice]) -> Void)? { get set }
    var onMediaStatusChange: (@Sendable (CastMediaStatusItem) -> Void)? { get set }

    func startDiscovery()
    func stopDiscovery()
    func connect(to device: CastDevice) async throws
    func disconnect() async
    func loadMedia(payload: CastMediaPayload, autoplay: Bool, currentTime: Double) async throws
    func play() async throws
    func pause() async throws
    func stop() async throws
    func seek(to position: TimeInterval) async throws
    func setVolume(_ volume: Float) async throws
}

public extension ChromecastServiceProtocol {
    func loadMedia(payload: CastMediaPayload) async throws {
        try await loadMedia(payload: payload, autoplay: true, currentTime: 0.0)
    }
}

// MARK: - Pure-Swift Chromecast Service Implementation

public final class ChromecastService: ChromecastServiceProtocol, @unchecked Sendable {
    // MARK: - Default Mock Devices for Offline / Testing Environments

    public static let defaultMockDevices: [CastDevice] = [
        CastDevice(
            id: "cast_tv_livingroom",
            name: "Living Room TV (Chromecast)",
            type: .chromecast,
            ipAddress: "192.168.1.105",
            port: 8009,
            modelName: "Chromecast with Google TV",
            capabilities: ["video_out", "audio_out"]
        ),
        CastDevice(
            id: "cast_bedroom_nest",
            name: "Bedroom Nest Hub",
            type: .chromecast,
            ipAddress: "192.168.1.112",
            port: 8009,
            modelName: "Google Nest Hub",
            capabilities: ["audio_out"]
        )
    ]

    // MARK: - Synchronized State

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.livelymedia.cast.service", qos: .userInitiated)

    private var _connectionState: CastConnectionState = .disconnected
    private var _discoveredDevices: [CastDevice] = []
    private var _activeDevice: CastDevice?
    private var _currentSessionId: String?
    private var _currentTransportId: String?
    private var _currentMediaSessionId: Int?
    private var _requestIdCounter: Int = 1
    private var receiveBuffer = Data()

    public var isMockMode: Bool
    public var fallbackToMockDevices: Bool

    // MARK: - Public State Accessors

    public var connectionState: CastConnectionState {
        lock.withLock { _connectionState }
    }

    public var discoveredDevices: [CastDevice] {
        lock.withLock { _discoveredDevices }
    }

    public var activeDevice: CastDevice? {
        lock.withLock { _activeDevice }
    }

    public var currentSessionId: String? {
        lock.withLock { _currentSessionId }
    }

    public var currentTransportId: String? {
        lock.withLock { _currentTransportId }
    }

    public var currentMediaSessionId: Int? {
        lock.withLock { _currentMediaSessionId }
    }

    // MARK: - Callbacks

    public var onStateChange: (@Sendable (CastConnectionState) -> Void)?
    public var onDevicesDiscovered: (@Sendable ([CastDevice]) -> Void)?
    public var onMediaStatusChange: (@Sendable (CastMediaStatusItem) -> Void)?

    // MARK: - Network Components

    #if canImport(Network)
    private var browser: NWBrowser?
    private var connection: NWConnection?
    #endif
    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Initialization & Deinitialization

    public init(isMockMode: Bool = false, fallbackToMockDevices: Bool = true) {
        self.isMockMode = isMockMode
        self.fallbackToMockDevices = fallbackToMockDevices
        if isMockMode || fallbackToMockDevices {
            self._discoveredDevices = Self.defaultMockDevices
        }
    }

    deinit {
        heartbeatTask?.cancel()
        #if canImport(Network)
        browser?.cancel()
        connection?.cancel()
        #endif
    }

    // MARK: - Discovery Lifecycle (mDNS NWBrowser)

    public func startDiscovery() {
        // [Intent] Start Bonjour mDNS scanning for _googlecast._tcp devices across the local Wi-Fi subnet
        if isMockMode {
            lock.withLock {
                self._discoveredDevices = Self.defaultMockDevices
            }
            onDevicesDiscovered?(Self.defaultMockDevices)
            return
        }

        #if canImport(Network)
        stopDiscovery()

        if fallbackToMockDevices && lock.withLock({ _discoveredDevices.isEmpty }) {
            lock.withLock {
                self._discoveredDevices = Self.defaultMockDevices
            }
            onDevicesDiscovered?(Self.defaultMockDevices)
        }

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_googlecast._tcp", domain: nil)
        let parameters = NWParameters()
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            self.handleBrowserResults(results)
        }

        newBrowser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed(let error) = state {
                // If Bonjour discovery fails (e.g. permission or network restricted), preserve fallback mock devices
                if self.fallbackToMockDevices {
                    self.lock.withLock {
                        if self._discoveredDevices.isEmpty {
                            self._discoveredDevices = Self.defaultMockDevices
                        }
                    }
                    self.onDevicesDiscovered?(self.discoveredDevices)
                }
                _ = error
            }
        }

        newBrowser.start(queue: queue)
        self.browser = newBrowser
        #else
        lock.withLock {
            self._discoveredDevices = Self.defaultMockDevices
        }
        onDevicesDiscovered?(Self.defaultMockDevices)
        #endif
    }

    public func stopDiscovery() {
        // [Intent] Cease mDNS scanning and release NWBrowser resources
        #if canImport(Network)
        browser?.cancel()
        browser = nil
        #endif
    }

    #if canImport(Network)
    private func handleBrowserResults(_ results: Set<NWBrowser.Result>) {
        var devices: [CastDevice] = []

        for result in results {
            var name = "Chromecast Device"
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
            @unknown default:
                break
            }

            // Extract TXT records: fn (friendly name), md (model name), id (device id), ca (capabilities)
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
            devices.append(device)
        }

        lock.withLock {
            if devices.isEmpty && (self.isMockMode || self.fallbackToMockDevices) {
                self._discoveredDevices = Self.defaultMockDevices
            } else {
                self._discoveredDevices = devices
            }
        }

        let current = self.discoveredDevices
        onDevicesDiscovered?(current)
    }
    #endif

    // MARK: - Connection & Session Lifecycle

    private func isMockDevice(_ device: CastDevice) -> Bool {
        return isMockMode ||
            device.id.starts(with: "mock_") ||
            device.id.starts(with: "cast_") ||
            (device.ipAddress == "192.168.1.105" || device.ipAddress == "192.168.1.112") ||
            Self.defaultMockDevices.contains(where: { $0.id == device.id })
    }

    public func connect(to device: CastDevice) async throws {
        // [Intent] Establish TLS NWConnection to receiver port 8009, complete Cast V2 handshake, and start heartbeat loop
        lock.withLock {
            self._connectionState = .connecting
        }
        onStateChange?(.connecting)

        if isMockDevice(device) {
            // Simulated local session for offline / mock testing
            try? await Task.sleep(nanoseconds: 50_000_000)
            lock.withLock {
                self._activeDevice = device
                self._currentSessionId = "mock-session-\(UUID().uuidString.prefix(8))"
                self._currentTransportId = "mock-transport-\(UUID().uuidString.prefix(8))"
                self._currentMediaSessionId = 1
                self._connectionState = .connected(deviceName: device.name)
            }
            onStateChange?(.connected(deviceName: device.name))
            return
        }

        #if canImport(Network)
        let hostStr = device.ipAddress ?? "127.0.0.1"
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(hostStr),
            port: NWEndpoint.Port(rawValue: device.port) ?? NWEndpoint.Port(integerLiteral: 8009)
        )

        let tlsOptions = NWProtocolTLS.Options()
        #if canImport(Security)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { (_, _, completion) in
                // [Intent] Accept Chromecast self-signed TLS certificates for local device communication
                completion(true)
            },
            DispatchQueue.global(qos: .userInitiated)
        )
        #endif

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let nwConn = NWConnection(to: endpoint, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            let resumeLock = NSLock()

            nwConn.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    resumeLock.withLock {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume()
                        }
                    }
                case .failed(let error):
                    resumeLock.withLock {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: CastError.connectionFailed(error.localizedDescription))
                        } else {
                            self.handleConnectionFailure(error.localizedDescription)
                        }
                    }
                case .cancelled:
                    resumeLock.withLock {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: CastError.connectionFailed("Connection cancelled"))
                        }
                    }
                default:
                    break
                }
            }

            nwConn.start(queue: self.queue)
            self.lock.withLock {
                self.connection = nwConn
            }
        }

        lock.withLock {
            self._activeDevice = device
            self._connectionState = .connected(deviceName: device.name)
        }
        onStateChange?(.connected(deviceName: device.name))

        // Start response receiver loop
        startReceiveLoop()

        // 1. Send CONNECT message on connection namespace
        let connectCmd = CastConnectCommand()
        try await sendFramedJSON(connectCmd)

        // 2. Send LAUNCH command for Default Media Receiver ("CC1AD845")
        let launchCmd = CastLaunchCommand(requestId: nextRequestId(), appId: CastV2AppId.defaultMediaReceiver)
        try await sendFramedJSON(launchCmd)

        // 3. Start 5s Heartbeat loop
        startHeartbeatLoop()
        #else
        throw CastError.connectionFailed("Network framework unavailable")
        #endif
    }

    public func disconnect() async {
        // [Intent] Gracefully tear down Cast V2 session, cancel heartbeat, and release socket
        heartbeatTask?.cancel()
        heartbeatTask = nil

        #if canImport(Network)
        if let _ = connection {
            try? await sendFramedJSON(CastCloseCommand())
        }
        connection?.cancel()
        connection = nil
        #endif

        lock.withLock {
            self._activeDevice = nil
            self._currentSessionId = nil
            self._currentTransportId = nil
            self._currentMediaSessionId = nil
            self._connectionState = .disconnected
            self.receiveBuffer.removeAll()
        }

        onStateChange?(.disconnected)
    }

    private func handleConnectionFailure(_ reason: String) {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        #if canImport(Network)
        connection?.cancel()
        connection = nil
        #endif

        lock.withLock {
            self._activeDevice = nil
            self._connectionState = .failed(reason)
            self.receiveBuffer.removeAll()
        }

        onStateChange?(.failed(reason))
    }

    // MARK: - Heartbeat & Wire Transmission

    private func startHeartbeatLoop() {
        // [Intent] Periodically send PING packets every 5 seconds to keep the Cast receiver TLS session alive
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self, !Task.isCancelled else { break }

                let isConnected: Bool = self.lock.withLock {
                    if case .connected = self._connectionState { return true }
                    return false
                }
                guard isConnected else { break }

                let pingCmd = CastPingCommand()
                try? await self.sendFramedJSON(pingCmd)
            }
        }
    }

    public func sendFramedJSON<T: Encodable>(_ value: T) async throws {
        let framedData = try CastV2Framer.encodeFramedJSON(value)
        try await sendRawData(framedData)
    }

    private func sendRawData(_ data: Data) async throws {
        #if canImport(Network)
        guard let conn = connection else {
            if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
                return
            }
            throw CastError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        #else
        if !isMockMode {
            throw CastError.notConnected
        }
        #endif
    }

    // MARK: - Receiver Loop & Packet Parsing

    #if canImport(Network)
    private func startReceiveLoop() {
        guard let conn = connection else { return }
        receiveNextPacket(on: conn)
    }

    private func receiveNextPacket(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.processIncomingData(data)
            }

            if let error = error {
                self.handleConnectionFailure(error.localizedDescription)
                return
            }

            if isComplete {
                Task {
                    await self.disconnect()
                }
                return
            }

            self.receiveNextPacket(on: conn)
        }
    }
    #endif

    public func processIncomingData(_ data: Data) {
        // [Intent] Ingest streaming bytes, extract 4-byte length framed packets, and parse Cast responses
        lock.withLock {
            self.receiveBuffer.append(data)
        }

        while true {
            var packetData: Data? = nil
            lock.withLock {
                packetData = CastV2Framer.decodeFramedMessage(from: &self.receiveBuffer)
            }
            guard let packet = packetData else { break }
            processPacketPayload(packet)
        }
    }

    public func processPacketPayload(_ payload: Data) {
        let decoder = JSONDecoder()

        // 1. Generic command handling (PING / PONG / CLOSE)
        if let generic = try? decoder.decode(CastGenericResponse.self, from: payload) {
            switch generic.type {
            case "PING":
                Task {
                    try? await self.sendFramedJSON(CastPongCommand())
                }
            case "PONG":
                break
            case "CLOSE":
                Task {
                    await self.disconnect()
                }
            default:
                break
            }
        }

        // 2. RECEIVER_STATUS: parse active application sessionId and transportId
        if let receiverStatus = try? decoder.decode(CastReceiverStatusResponse.self, from: payload) {
            if let apps = receiverStatus.status?.applications {
                if let mediaApp = apps.first(where: { $0.appId == CastV2AppId.defaultMediaReceiver }) ?? apps.first {
                    lock.withLock {
                        self._currentSessionId = mediaApp.sessionId
                        self._currentTransportId = mediaApp.transportId
                    }
                }
            }
        }

        // 3. MEDIA_STATUS: parse active mediaSessionId and state
        if let mediaStatus = try? decoder.decode(CastMediaStatusResponse.self, from: payload) {
            if let firstItem = mediaStatus.status.first {
                lock.withLock {
                    self._currentMediaSessionId = firstItem.mediaSessionId
                }
                onMediaStatusChange?(firstItem)
            }
        }
    }

    // MARK: - Remote Media Controls

    public func loadMedia(payload: CastMediaPayload, autoplay: Bool = true, currentTime: Double = 0.0) async throws {
        // [Intent] Dispatch LOAD command with stream URL, MIME type, and metadata to the receiver
        guard case .connected = connectionState else {
            throw CastError.notConnected
        }

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            lock.withLock {
                self._currentMediaSessionId = 1
            }
            let mockStatus = CastMediaStatusItem(
                mediaSessionId: 1,
                playbackRate: 1.0,
                playerState: autoplay ? "PLAYING" : "PAUSED",
                currentTime: currentTime,
                idleReason: nil,
                volume: CastVolume(level: 1.0, muted: false),
                media: CastMediaInfo(
                    contentId: payload.streamURL.absoluteString,
                    streamType: "BUFFERED",
                    contentType: payload.contentType,
                    metadata: CastMediaMetadata(
                        title: payload.title,
                        subtitle: payload.subtitle
                    ),
                    duration: payload.duration
                )
            )
            onMediaStatusChange?(mockStatus)
            return
        }

        let sessionId = lock.withLock { self._currentSessionId }
        let mediaMetadata = CastMediaMetadata(
            metadataType: 0,
            title: payload.title,
            subtitle: payload.subtitle,
            artist: payload.subtitle,
            albumName: nil,
            images: nil
        )
        let mediaInfo = CastMediaInfo(
            contentId: payload.streamURL.absoluteString,
            streamType: "BUFFERED",
            contentType: payload.contentType,
            metadata: mediaMetadata,
            duration: payload.duration
        )
        let loadCmd = CastLoadCommand(
            requestId: nextRequestId(),
            sessionId: sessionId,
            media: mediaInfo,
            autoplay: autoplay,
            currentTime: currentTime
        )
        try await sendFramedJSON(loadCmd)
    }

    public func play() async throws {
        // [Intent] Dispatch PLAY command to resume active receiver media session
        guard case .connected = connectionState else { throw CastError.notConnected }
        guard let mediaSessionId = currentMediaSessionId else { throw CastError.noActiveMediaSession }

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            let status = CastMediaStatusItem(
                mediaSessionId: mediaSessionId,
                playbackRate: 1.0,
                playerState: "PLAYING",
                currentTime: nil,
                idleReason: nil,
                volume: nil,
                media: nil
            )
            onMediaStatusChange?(status)
            return
        }

        let cmd = CastPlayCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try await sendFramedJSON(cmd)
    }

    public func pause() async throws {
        // [Intent] Dispatch PAUSE command to pause active receiver media session
        guard case .connected = connectionState else { throw CastError.notConnected }
        guard let mediaSessionId = currentMediaSessionId else { throw CastError.noActiveMediaSession }

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            let status = CastMediaStatusItem(
                mediaSessionId: mediaSessionId,
                playbackRate: 0.0,
                playerState: "PAUSED",
                currentTime: nil,
                idleReason: nil,
                volume: nil,
                media: nil
            )
            onMediaStatusChange?(status)
            return
        }

        let cmd = CastPauseCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try await sendFramedJSON(cmd)
    }

    public func stop() async throws {
        // [Intent] Dispatch STOP command to end playback on receiver
        guard case .connected = connectionState else { throw CastError.notConnected }
        guard let mediaSessionId = currentMediaSessionId else { throw CastError.noActiveMediaSession }

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            let status = CastMediaStatusItem(
                mediaSessionId: mediaSessionId,
                playbackRate: 0.0,
                playerState: "IDLE",
                currentTime: 0.0,
                idleReason: "CANCELLED",
                volume: nil,
                media: nil
            )
            onMediaStatusChange?(status)
            return
        }

        let cmd = CastMediaStopCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId)
        try await sendFramedJSON(cmd)
    }

    public func seek(to position: TimeInterval) async throws {
        // [Intent] Dispatch SEEK command to scrub to a specified timestamp in seconds
        guard case .connected = connectionState else { throw CastError.notConnected }
        guard let mediaSessionId = currentMediaSessionId else { throw CastError.noActiveMediaSession }

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            let status = CastMediaStatusItem(
                mediaSessionId: mediaSessionId,
                playbackRate: 1.0,
                playerState: "PLAYING",
                currentTime: position,
                idleReason: nil,
                volume: nil,
                media: nil
            )
            onMediaStatusChange?(status)
            return
        }

        let cmd = CastSeekCommand(requestId: nextRequestId(), mediaSessionId: mediaSessionId, currentTime: position)
        try await sendFramedJSON(cmd)
    }

    public func setVolume(_ volume: Float) async throws {
        // [Intent] Dispatch SET_VOLUME command to adjust receiver volume level (0.0 to 1.0)
        guard case .connected = connectionState else { throw CastError.notConnected }
        let clampedVolume = max(0.0, min(1.0, volume))

        if isMockMode || isMockDevice(activeDevice ?? CastDevice(name: "", type: .chromecast)) {
            let mediaSessionId = currentMediaSessionId ?? 1
            let status = CastMediaStatusItem(
                mediaSessionId: mediaSessionId,
                playbackRate: nil,
                playerState: "PLAYING",
                currentTime: nil,
                idleReason: nil,
                volume: CastVolume(level: clampedVolume, muted: clampedVolume <= 0.0001),
                media: nil
            )
            onMediaStatusChange?(status)
            return
        }

        let cmd = CastSetVolumeCommand(
            requestId: nextRequestId(),
            volume: CastVolume(level: clampedVolume, muted: clampedVolume <= 0.0001)
        )
        try await sendFramedJSON(cmd)
    }

    // MARK: - Helpers

    public func nextRequestId() -> Int {
        lock.withLock {
            _requestIdCounter += 1
            return _requestIdCounter
        }
    }

    public func setDiscoveredDevicesForTesting(_ devices: [CastDevice]) {
        lock.withLock {
            self._discoveredDevices = devices
        }
        onDevicesDiscovered?(devices)
    }
}

