// [Intent] MainActor CastCoordinator unifying AirPlay 2 and Google Cast discovery, route switching, and stream bridging
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
    @Published public var isCastSheetPresented: Bool = false

    private let chromecastService: ChromecastServiceProtocol
    private let streamBridge: ChromecastStreamBridgeProtocol
    private let airPlayManager: AirPlayManagerProtocol
    private let playbackCoordinator: PlaybackCoordinator

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
        chromecastService.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.connectionState = state
                if case .connected = state {
                    self.activeTarget = .chromecast
                } else if case .disconnected = state {
                    self.activeTarget = .localDevice
                }
            }
        }
    }

    public func startDiscovery() {
        chromecastService.startDiscovery()
        self.availableDevices = chromecastService.discoveredDevices
    }

    public func stopDiscovery() {
        chromecastService.stopDiscovery()
    }

    public func castCurrentItem(to device: CastDevice, serverPort: UInt16 = 8080, customHost: String? = nil) async throws {
        guard let currentItem = playbackCoordinator.currentItem else { return }

        try await chromecastService.connect(to: device)
        let payload = streamBridge.generateCastPayload(for: currentItem, serverPort: serverPort, customHost: customHost)
        try await chromecastService.loadMedia(payload: payload)

        // Pause local player since receiver is now playing
        playbackCoordinator.pause()
    }

    public func disconnectCast() async {
        await chromecastService.disconnect()
        self.activeTarget = .localDevice
    }
}
