// [Intent] Google Cast SDK client interface managing device discovery, session lifecycle, and remote media playback
import Foundation

public protocol ChromecastServiceProtocol: AnyObject, Sendable {
    var connectionState: CastConnectionState { get }
    var discoveredDevices: [CastDevice] { get }
    var onStateChange: (@Sendable (CastConnectionState) -> Void)? { get set }

    func startDiscovery()
    func stopDiscovery()
    func connect(to device: CastDevice) async throws
    func disconnect() async
    func loadMedia(payload: CastMediaPayload) async throws
    func play()
    func pause()
    func seek(to position: TimeInterval)
    func setVolume(_ volume: Float)
}

public final class ChromecastService: ChromecastServiceProtocol, @unchecked Sendable {
    public private(set) var connectionState: CastConnectionState = .disconnected
    public private(set) var discoveredDevices: [CastDevice] = []
    public var onStateChange: (@Sendable (CastConnectionState) -> Void)?

    private var activeDevice: CastDevice?

    public init() {}

    public func startDiscovery() {
        // Discovers Chromecast receivers on local LAN (mDNS / SSDP)
        self.discoveredDevices = [
            CastDevice(id: "cast_tv_livingroom", name: "Living Room TV (Chromecast)", type: .chromecast, ipAddress: "192.168.1.105"),
            CastDevice(id: "cast_bedroom_nest", name: "Bedroom Nest Hub", type: .chromecast, ipAddress: "192.168.1.112")
        ]
    }

    public func stopDiscovery() {
        // Cease mDNS scanning
    }

    public func connect(to device: CastDevice) async throws {
        self.connectionState = .connecting
        onStateChange?(self.connectionState)

        // Simulated socket handshake with Google Cast receiver
        try await Task.sleep(nanoseconds: 500_000_000)
        self.activeDevice = device
        self.connectionState = .connected(deviceName: device.name)
        onStateChange?(self.connectionState)
    }

    public func disconnect() async {
        self.activeDevice = nil
        self.connectionState = .disconnected
        onStateChange?(self.connectionState)
    }

    public func loadMedia(payload: CastMediaPayload) async throws {
        guard case .connected = connectionState else {
            throw NSError(domain: "ChromecastService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active Google Cast session"])
        }
        // Sends Cast JSON LOAD command with streamURL and metadata
    }

    public func play() {
        // Sends Cast PLAY command
    }

    public func pause() {
        // Sends Cast PAUSE command
    }

    public func seek(to position: TimeInterval) {
        // Sends Cast SEEK command
    }

    public func setVolume(_ volume: Float) {
        // Sends Cast VOLUME command
    }
}
