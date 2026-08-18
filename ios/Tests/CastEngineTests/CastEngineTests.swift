// [Intent] Unit tests verifying Chromecast stream bridge URL generation and Cast device state transitions
import XCTest
import CoreStorage
@testable import CastEngine

final class CastEngineTests: XCTestCase {
    func testChromecastStreamBridgePayloadGeneration() {
        let bridge = ChromecastStreamBridge()
        let item = MediaItem(
            title: "Test Movie 1080p",
            filePath: "/sandbox/video/movie.mp4",
            fileName: "movie.mp4",
            fileSize: 500_000_000,
            duration: 1800.0,
            mediaType: .video,
            containerFormat: "mp4",
            artist: "Studio Director"
        )

        let payload = bridge.generateCastPayload(for: item, serverPort: 8080, customHost: "192.168.1.50")

        XCTAssertEqual(payload.streamURL.absoluteString, "http://192.168.1.50:8080/stream/movie.mp4")
        XCTAssertEqual(payload.contentType, "video/mp4")
        XCTAssertEqual(payload.title, "Test Movie 1080p")
        XCTAssertEqual(payload.subtitle, "Studio Director")
        XCTAssertEqual(payload.duration, 1800.0)
    }

    func testChromecastServiceDiscoveryAndConnect() async throws {
        let service = ChromecastService()
        service.startDiscovery()

        XCTAssertFalse(service.discoveredDevices.isEmpty)
        let target = service.discoveredDevices[0]

        try await service.connect(to: target)
        if case .connected(let name) = service.connectionState {
            XCTAssertEqual(name, target.name)
        } else {
            XCTFail("Service must be in connected state")
        }

        await service.disconnect()
        XCTAssertEqual(service.connectionState, .disconnected)
    }
}
