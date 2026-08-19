// [Intent] MainActor CastCoordinator unifying AirPlay 2 and Google Cast discovery, route switching, remote playback controls, and stream bridging
import Foundation
import SwiftUI
import Combine
import CoreStorage
import PlaybackEngine

@MainActor
public final class CastCoordinator: ObservableObject {
    public static let shared = CastCoordinator()

    @Published public private(set) var activeTarget: CastTargetType = .localDevice
    @Published public private(set) var connectionState: CastConnectionState = .disconnected
    @Published public private(set) var availableDevices: [CastDevice] = []
    @Published public private(set) var currentMediaStatus: CastMediaStatusItem?
    @Published public var isCastSheetPresented: Bool = false

    private let chromecastService: ChromecastServiceProtocol
    private let streamBridge: ChromecastStreamBridgeProtocol
    private let airPlayManager: AirPlayManagerProtocol
    private let playbackCoordinator: PlaybackCoordinator

    public var isAirPlayActive: Bool {
        airPlayManager.isAirPlayActive
    }

    public var activeAirPlayDeviceName: String? {
        airPlayManager.activeAirPlayDeviceName
    }

    public init(
        chromecastService: ChromecastServiceProtocol = ChromecastService(),
        streamBridge: ChromecastStreamBridgeProtocol = ChromecastStreamBridge(),
        airPlayManager: AirPlayManagerProtocol = AirPlayManager.shared,
        playbackCoordinator: PlaybackCoordinator? = nil
    ) {
        self.chromecastService = chromecastService
        self.streamBridge = streamBridge
        self.airPlayManager = airPlayManager
        self.playbackCoordinator = playbackCoordinator ?? PlaybackCoordinator.shared

        setupCallbacks()
    }

    private func setupCallbacks() {
        // [Intent] Connect ChromecastService callbacks to MainActor published UI properties
        chromecastService.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.connectionState = state
                if case .connected = state {
                    self.activeTarget = .chromecast
                } else if case .disconnected = state {
                    self.activeTarget = .localDevice
                    self.currentMediaStatus = nil
                } else if case .failed = state {
                    self.activeTarget = .localDevice
                    self.currentMediaStatus = nil
                }
            }
        }

        chromecastService.onDevicesDiscovered = { [weak self] devices in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.availableDevices = devices
            }
        }

        chromecastService.onMediaStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentMediaStatus = status
            }
        }
    }

    // MARK: - Device Discovery

    public func startDiscovery() {
        chromecastService.startDiscovery()
        self.availableDevices = chromecastService.discoveredDevices
    }

    public func stopDiscovery() {
        chromecastService.stopDiscovery()
    }

    // MARK: - Media Casting

    public func castCurrentItem(to device: CastDevice, serverPort: UInt16 = 8080, customHost: String? = nil) async throws {
        guard let currentItem = playbackCoordinator.currentItem else { return }
        try await castMediaItem(currentItem, to: device, serverPort: serverPort, customHost: customHost)
    }

    public func castMediaItem(_ item: MediaItem, to device: CastDevice, serverPort: UInt16 = 8080, customHost: String? = nil) async throws {
        try await chromecastService.connect(to: device)
        let payload = streamBridge.generateCastPayload(for: item, serverPort: serverPort, customHost: customHost)
        try await chromecastService.loadMedia(payload: payload)

        // Pause local player since receiver is now playing
        playbackCoordinator.pause()
    }

    public func disconnectCast() async {
        await chromecastService.disconnect()
        self.activeTarget = .localDevice
        self.currentMediaStatus = nil
    }

    // MARK: - Remote Playback Controls

    public func play() async throws {
        try await chromecastService.play()
    }

    public func pause() async throws {
        try await chromecastService.pause()
    }

    public func stop() async throws {
        try await chromecastService.stop()
    }

    public func seek(to position: TimeInterval) async throws {
        try await chromecastService.seek(to: position)
    }

    public func setVolume(_ volume: Float) async throws {
        try await chromecastService.setVolume(volume)
    }
}

