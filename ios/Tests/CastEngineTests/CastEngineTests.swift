// [Intent] Unit tests verifying Cast V2 framing, payload serialization, media control commands, status decoding, and stream bridging
import XCTest
import CoreStorage
@testable import CastEngine

final class CastEngineTests: XCTestCase {
    // MARK: - Framing Tests

    func testCastV2FramerEncodeAndDecode() {
        let payloadString = "{\"type\":\"PING\"}"
        let payloadData = Data(payloadString.utf8)

        // 1. Encode with 4-byte big-endian prefix
        let framedData = CastV2Framer.encodeFramedMessage(payloadData)
        XCTAssertEqual(framedData.count, 4 + payloadData.count)

        // Verify big-endian length prefix header
        let expectedLength = UInt32(payloadData.count)
        var readLength: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &readLength) { ptr in
            framedData.copyBytes(to: ptr, count: 4)
        }
        XCTAssertEqual(UInt32(bigEndian: readLength), expectedLength)

        // 2. Decode back from buffer
        var buffer = framedData
        let decoded = CastV2Framer.decodeFramedMessage(from: &buffer)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, payloadData)
        XCTAssertTrue(buffer.isEmpty, "Buffer should be empty after extracting complete frame")
    }

    func testCastV2FramerPartialAndMultiplePackets() {
        let msg1 = Data("{\"type\":\"PING\"}".utf8)
        let msg2 = Data("{\"type\":\"PONG\"}".utf8)

        let framed1 = CastV2Framer.encodeFramedMessage(msg1)
        let framed2 = CastV2Framer.encodeFramedMessage(msg2)

        // Case A: Partial buffer (less than 4 bytes)
        var partialBuffer = framed1.prefix(2)
        XCTAssertNil(CastV2Framer.decodeFramedMessage(from: &partialBuffer))
        XCTAssertEqual(partialBuffer.count, 2, "Partial buffer must not be modified")

        // Case B: Partial payload (header present but incomplete body)
        var partialBodyBuffer = framed1.prefix(framed1.count - 2)
        XCTAssertNil(CastV2Framer.decodeFramedMessage(from: &partialBodyBuffer))
        XCTAssertEqual(partialBodyBuffer.count, framed1.count - 2)

        // Case C: Multiple packets in a single TCP buffer stream
        var streamBuffer = framed1 + framed2
        let extracted1 = CastV2Framer.decodeFramedMessage(from: &streamBuffer)
        XCTAssertEqual(extracted1, msg1)
        XCTAssertEqual(streamBuffer, framed2)

        let extracted2 = CastV2Framer.decodeFramedMessage(from: &streamBuffer)
        XCTAssertEqual(extracted2, msg2)
        XCTAssertTrue(streamBuffer.isEmpty)
    }

    // MARK: - Protocol Payload Serialization Tests

    func testCastLoadCommandSerialization() throws {
        let mediaMetadata = CastMediaMetadata(
            metadataType: 0,
            title: "Tears of Steel 4K",
            subtitle: "Blender Open Movie",
            artist: "Ian Hubert",
            albumName: "Sci-Fi Shorts",
            images: [CastImage(url: "http://192.168.1.50:8080/thumb.jpg", height: 720, width: 1280)]
        )

        let mediaInfo = CastMediaInfo(
            contentId: "http://192.168.1.50:8080/stream/movie.mp4",
            streamType: "BUFFERED",
            contentType: "video/mp4",
            metadata: mediaMetadata,
            duration: 734.0
        )

        let loadCommand = CastLoadCommand(
            requestId: 42,
            sessionId: "session-abc-123",
            media: mediaInfo,
            autoplay: true,
            currentTime: 15.5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(loadCommand)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(jsonString.contains("\"type\":\"LOAD\""))
        XCTAssertTrue(jsonString.contains("\"requestId\":42"))
        XCTAssertTrue(jsonString.contains("\"contentId\":\"http:\\/\\/192.168.1.50:8080\\/stream\\/movie.mp4\"") || jsonString.contains("\"contentId\":\"http://192.168.1.50:8080/stream/movie.mp4\""))
        XCTAssertTrue(jsonString.contains("\"title\":\"Tears of Steel 4K\""))
        XCTAssertTrue(jsonString.contains("\"autoplay\":true"))

        // Decode round-trip
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CastLoadCommand.self, from: data)
        XCTAssertEqual(decoded, loadCommand)
    }

    func testCastControlCommandsSerialization() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // 1. PLAY
        let play = CastPlayCommand(requestId: 101, mediaSessionId: 7)
        let playData = try encoder.encode(play)
        let decodedPlay = try decoder.decode(CastPlayCommand.self, from: playData)
        XCTAssertEqual(decodedPlay.type, "PLAY")
        XCTAssertEqual(decodedPlay.requestId, 101)
        XCTAssertEqual(decodedPlay.mediaSessionId, 7)

        // 2. PAUSE
        let pause = CastPauseCommand(requestId: 102, mediaSessionId: 7)
        let pauseData = try encoder.encode(pause)
        let decodedPause = try decoder.decode(CastPauseCommand.self, from: pauseData)
        XCTAssertEqual(decodedPause.type, "PAUSE")
        XCTAssertEqual(decodedPause.mediaSessionId, 7)

        // 3. STOP
        let stop = CastMediaStopCommand(requestId: 103, mediaSessionId: 7)
        let stopData = try encoder.encode(stop)
        let decodedStop = try decoder.decode(CastMediaStopCommand.self, from: stopData)
        XCTAssertEqual(decodedStop.type, "STOP")

        // 4. SEEK
        let seek = CastSeekCommand(requestId: 104, mediaSessionId: 7, currentTime: 128.5)
        let seekData = try encoder.encode(seek)
        let decodedSeek = try decoder.decode(CastSeekCommand.self, from: seekData)
        XCTAssertEqual(decodedSeek.type, "SEEK")
        XCTAssertEqual(decodedSeek.currentTime, 128.5)
        XCTAssertEqual(decodedSeek.resumeState, "PLAYBACK_START")

        // 5. SET_VOLUME
        let volumeCmd = CastSetVolumeCommand(requestId: 105, volume: CastVolume(level: 0.75, muted: false))
        let volumeData = try encoder.encode(volumeCmd)
        let decodedVolume = try decoder.decode(CastSetVolumeCommand.self, from: volumeData)
        XCTAssertEqual(decodedVolume.type, "SET_VOLUME")
        XCTAssertEqual(decodedVolume.volume.level, 0.75)
        XCTAssertEqual(decodedVolume.volume.muted, false)
    }

    func testCastMediaStatusResponseDecoding() throws {
        let json = """
        {
            "type": "MEDIA_STATUS",
            "requestId": 99,
            "status": [
                {
                    "mediaSessionId": 3,
                    "playbackRate": 1.0,
                    "playerState": "PLAYING",
                    "currentTime": 45.2,
                    "idleReason": null,
                    "volume": {
                        "level": 0.9,
                        "muted": false
                    },
                    "media": {
                        "contentId": "http://192.168.1.50:8080/stream/movie.mp4",
                        "streamType": "BUFFERED",
                        "contentType": "video/mp4",
                        "duration": 734.0
                    }
                }
            ]
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CastMediaStatusResponse.self, from: data)

        XCTAssertEqual(response.type, "MEDIA_STATUS")
        XCTAssertEqual(response.requestId, 99)
        XCTAssertEqual(response.status.count, 1)

        let status = response.status[0]
        XCTAssertEqual(status.mediaSessionId, 3)
        XCTAssertEqual(status.playerState, "PLAYING")
        XCTAssertEqual(status.currentTime, 45.2)
        XCTAssertEqual(status.playbackRate, 1.0)
        XCTAssertEqual(status.volume?.level, 0.9)
        XCTAssertEqual(status.volume?.muted, false)
        XCTAssertEqual(status.media?.contentId, "http://192.168.1.50:8080/stream/movie.mp4")
        XCTAssertEqual(status.media?.contentType, "video/mp4")
        XCTAssertEqual(status.media?.duration, 734.0)
    }

    func testCastReceiverStatusResponseDecoding() throws {
        let json = """
        {
            "type": "RECEIVER_STATUS",
            "requestId": 1,
            "status": {
                "applications": [
                    {
                        "appId": "CC1AD845",
                        "displayName": "Default Media Receiver",
                        "sessionId": "b48c12a7-f58c-4a55",
                        "statusText": "Default Media Receiver Application",
                        "transportId": "web-99"
                    }
                ],
                "isStandBy": false,
                "volume": {
                    "level": 1.0,
                    "muted": false
                }
            }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CastReceiverStatusResponse.self, from: data)

        XCTAssertEqual(response.type, "RECEIVER_STATUS")
        XCTAssertEqual(response.requestId, 1)
        XCTAssertEqual(response.status?.applications?.count, 1)

        let app = response.status?.applications?[0]
        XCTAssertEqual(app?.appId, CastV2AppId.defaultMediaReceiver)
        XCTAssertEqual(app?.displayName, "Default Media Receiver")
        XCTAssertEqual(app?.sessionId, "b48c12a7-f58c-4a55")
        XCTAssertEqual(app?.transportId, "web-99")
    }

    func testCastDeviceEnhancements() throws {
        let device = CastDevice(
            id: "living-room-tv",
            name: "Living Room Chromecast",
            type: .chromecast,
            ipAddress: "192.168.1.105",
            port: 8009,
            modelName: "Chromecast with Google TV",
            capabilities: ["video_out", "audio_out"]
        )

        XCTAssertEqual(device.id, "living-room-tv")
        XCTAssertEqual(device.name, "Living Room Chromecast")
        XCTAssertEqual(device.port, 8009)
        XCTAssertEqual(device.modelName, "Chromecast with Google TV")
        XCTAssertEqual(device.capabilities, ["video_out", "audio_out"])

        // Test Codable conformance
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(CastDevice.self, from: data)
        XCTAssertEqual(decoded, device)
    }

    // MARK: - Legacy Stream Bridge & Discovery Integration

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

