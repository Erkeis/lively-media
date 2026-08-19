// [Intent] Unit tests verifying Cast V2 framing, payload serialization, media control commands, status decoding, stream bridging, NW discovery, session lifecycle, and CastCoordinator integration
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

    // MARK: - Stream Bridge & Discovery Integration

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
        let service = ChromecastService(isMockMode: true)
        nonisolated(unsafe) var discoveredList: [CastDevice] = []
        let discoveryLock = NSLock()
        service.onDevicesDiscovered = { devices in
            discoveryLock.withLock {
                discoveredList = devices
            }
        }

        service.startDiscovery()
        XCTAssertFalse(service.discoveredDevices.isEmpty)
        let discoveredCount = discoveryLock.withLock { discoveredList.count }
        XCTAssertGreaterThan(discoveredCount, 0)

        let target = service.discoveredDevices[0]
        nonisolated(unsafe) var stateTransitions: [CastConnectionState] = []
        let stateLock = NSLock()
        service.onStateChange = { state in
            stateLock.withLock {
                stateTransitions.append(state)
            }
        }

        try await service.connect(to: target)

        if case .connected(let name) = service.connectionState {
            XCTAssertEqual(name, target.name)
        } else {
            XCTFail("Service must be in connected state")
        }

        XCTAssertNotNil(service.currentSessionId)
        XCTAssertNotNil(service.currentTransportId)
        XCTAssertEqual(service.currentMediaSessionId, 1)

        await service.disconnect()
        XCTAssertEqual(service.connectionState, .disconnected)
        XCTAssertNil(service.currentSessionId)
        XCTAssertNil(service.currentMediaSessionId)
    }

    func testChromecastServiceRemoteMediaControls() async throws {
        let service = ChromecastService(isMockMode: true)
        let target = ChromecastService.defaultMockDevices[0]
        try await service.connect(to: target)

        nonisolated(unsafe) var lastStatus: CastMediaStatusItem?
        let statusLock = NSLock()
        service.onMediaStatusChange = { status in
            statusLock.withLock {
                lastStatus = status
            }
        }

        // 1. Load Media
        let payload = CastMediaPayload(
            streamURL: URL(string: "http://192.168.1.50:8080/stream/song.mp3")!,
            contentType: "audio/mpeg",
            title: "Synthwave Track",
            subtitle: "Artist X",
            duration: 240.0
        )
        try await service.loadMedia(payload: payload, autoplay: true, currentTime: 10.0)

        let currentStatus1 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus1?.playerState, "PLAYING")
        XCTAssertEqual(currentStatus1?.media?.metadata?.title, "Synthwave Track")
        XCTAssertEqual(currentStatus1?.media?.title, "Synthwave Track")
        XCTAssertEqual(currentStatus1?.currentTime, 10.0)

        // 2. Pause
        try await service.pause()
        let currentStatus2 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus2?.playerState, "PAUSED")

        // 3. Play
        try await service.play()
        let currentStatus3 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus3?.playerState, "PLAYING")

        // 4. Seek
        try await service.seek(to: 95.5)
        let currentStatus4 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus4?.currentTime, 95.5)

        // 5. Set Volume
        try await service.setVolume(0.65)
        let currentStatus5 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus5?.volume?.level, 0.65)

        // 6. Stop
        try await service.stop()
        let currentStatus6 = statusLock.withLock { lastStatus }
        XCTAssertEqual(currentStatus6?.playerState, "IDLE")
        XCTAssertEqual(currentStatus6?.idleReason, "CANCELLED")

        await service.disconnect()
    }

    func testChromecastServicePacketParsingAndSessionTracking() {
        let service = ChromecastService(isMockMode: true)

        // 1. Process Framed RECEIVER_STATUS
        let receiverJson = """
        {
            "type": "RECEIVER_STATUS",
            "requestId": 12,
            "status": {
                "applications": [
                    {
                        "appId": "CC1AD845",
                        "displayName": "Default Media Receiver",
                        "sessionId": "live-sess-999",
                        "statusText": "Ready",
                        "transportId": "live-transport-888"
                    }
                ]
            }
        }
        """
        let framedReceiverData = CastV2Framer.encodeFramedString(receiverJson)
        service.processIncomingData(framedReceiverData)

        XCTAssertEqual(service.currentSessionId, "live-sess-999")
        XCTAssertEqual(service.currentTransportId, "live-transport-888")

        // 2. Process Framed MEDIA_STATUS
        nonisolated(unsafe) var receivedMediaStatus: CastMediaStatusItem?
        let mediaStatusLock = NSLock()
        service.onMediaStatusChange = { status in
            mediaStatusLock.withLock {
                receivedMediaStatus = status
            }
        }

        let mediaJson = """
        {
            "type": "MEDIA_STATUS",
            "requestId": 13,
            "status": [
                {
                    "mediaSessionId": 42,
                    "playbackRate": 1.0,
                    "playerState": "BUFFERING",
                    "currentTime": 12.0
                }
            ]
        }
        """
        let framedMediaData = CastV2Framer.encodeFramedString(mediaJson)
        service.processIncomingData(framedMediaData)

        let finalMediaStatus = mediaStatusLock.withLock { receivedMediaStatus }
        XCTAssertEqual(service.currentMediaSessionId, 42)
        XCTAssertEqual(finalMediaStatus?.mediaSessionId, 42)
        XCTAssertEqual(finalMediaStatus?.playerState, "BUFFERING")
    }

    func testCastErrorDescriptions() {
        let notConnected = CastError.notConnected
        XCTAssertEqual(notConnected.errorDescription, "No active Google Cast session")

        let connectionFailed = CastError.connectionFailed("Host unreachable")
        XCTAssertEqual(connectionFailed.errorDescription, "Google Cast connection failed: Host unreachable")

        let timeout = CastError.connectionTimeout
        XCTAssertEqual(timeout.errorDescription, "Google Cast connection timed out")

        let noMedia = CastError.noActiveMediaSession
        XCTAssertEqual(noMedia.errorDescription, "No active media session on Google Cast receiver")

        let invalidPayload = CastError.invalidPayload
        XCTAssertEqual(invalidPayload.errorDescription, "Invalid Cast media payload")

        let cmdFailed = CastError.commandFailed("Network write error")
        XCTAssertEqual(cmdFailed.errorDescription, "Cast command failed: Network write error")
    }

    // MARK: - CastCoordinator Integration Tests

    @MainActor
    func testCastCoordinatorIntegration() async throws {
        let mockService = ChromecastService(isMockMode: true)
        let coordinator = CastCoordinator(chromecastService: mockService)

        coordinator.startDiscovery()
        XCTAssertFalse(coordinator.availableDevices.isEmpty)

        let targetDevice = coordinator.availableDevices[0]
        let testItem = MediaItem(
            title: "Test Movie HD",
            filePath: "/sandbox/movie.mp4",
            fileName: "movie.mp4",
            fileSize: 100_000_000,
            duration: 600.0,
            mediaType: .video,
            containerFormat: "mp4"
        )

        try await coordinator.castMediaItem(testItem, to: targetDevice, serverPort: 8080, customHost: "192.168.1.10")

        if case .connected(let name) = coordinator.connectionState {
            XCTAssertEqual(name, targetDevice.name)
        } else {
            XCTFail("Coordinator connection state should be connected")
        }
        XCTAssertEqual(coordinator.activeTarget, .chromecast)

        // Remote playback controls delegation through coordinator
        try await coordinator.pause()
        XCTAssertEqual(coordinator.currentMediaStatus?.playerState, "PAUSED")

        try await coordinator.play()
        XCTAssertEqual(coordinator.currentMediaStatus?.playerState, "PLAYING")

        try await coordinator.seek(to: 45.0)
        XCTAssertEqual(coordinator.currentMediaStatus?.currentTime, 45.0)

        try await coordinator.setVolume(0.8)
        XCTAssertEqual(coordinator.currentMediaStatus?.volume?.level, 0.8)

        try await coordinator.stop()
        XCTAssertEqual(coordinator.currentMediaStatus?.playerState, "IDLE")

        await coordinator.disconnectCast()
        XCTAssertEqual(coordinator.connectionState, .disconnected)
        XCTAssertEqual(coordinator.activeTarget, .localDevice)
        XCTAssertNil(coordinator.currentMediaStatus)
    }

    // MARK: - Extended Protocol & Error Handling Tests

    func testCastHeartbeatAndLifecycleCommandsSerialization() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // 1. CONNECT & CLOSE
        let connectCmd = CastConnectCommand(package: "com.livelymedia")
        let connectData = try encoder.encode(connectCmd)
        let decodedConnect = try decoder.decode(CastConnectCommand.self, from: connectData)
        XCTAssertEqual(decodedConnect.type, "CONNECT")
        XCTAssertEqual(decodedConnect.package, "com.livelymedia")

        let closeCmd = CastCloseCommand()
        let closeData = try encoder.encode(closeCmd)
        let decodedClose = try decoder.decode(CastCloseCommand.self, from: closeData)
        XCTAssertEqual(decodedClose.type, "CLOSE")

        // 2. PING & PONG
        let pingCmd = CastPingCommand()
        let pingData = try encoder.encode(pingCmd)
        let decodedPing = try decoder.decode(CastPingCommand.self, from: pingData)
        XCTAssertEqual(decodedPing.type, "PING")

        let pongCmd = CastPongCommand()
        let pongData = try encoder.encode(pongCmd)
        let decodedPong = try decoder.decode(CastPongCommand.self, from: pongData)
        XCTAssertEqual(decodedPong.type, "PONG")

        // 3. LAUNCH, GET_STATUS, STOP
        let launchCmd = CastLaunchCommand(requestId: 10, appId: CastV2AppId.defaultMediaReceiver)
        let launchData = try encoder.encode(launchCmd)
        let decodedLaunch = try decoder.decode(CastLaunchCommand.self, from: launchData)
        XCTAssertEqual(decodedLaunch.type, "LAUNCH")
        XCTAssertEqual(decodedLaunch.appId, "CC1AD845")

        let getStatusCmd = CastReceiverGetStatusCommand(requestId: 11)
        let getStatusData = try encoder.encode(getStatusCmd)
        let decodedGetStatus = try decoder.decode(CastReceiverGetStatusCommand.self, from: getStatusData)
        XCTAssertEqual(decodedGetStatus.type, "GET_STATUS")

        let stopCmd = CastReceiverStopCommand(requestId: 12, sessionId: "session-99")
        let stopData = try encoder.encode(stopCmd)
        let decodedStop = try decoder.decode(CastReceiverStopCommand.self, from: stopData)
        XCTAssertEqual(decodedStop.type, "STOP")
        XCTAssertEqual(decodedStop.sessionId, "session-99")

        let mediaStatusCmd = CastMediaGetStatusCommand(requestId: 13, mediaSessionId: 5)
        let mediaStatusData = try encoder.encode(mediaStatusCmd)
        let decodedMediaStatus = try decoder.decode(CastMediaGetStatusCommand.self, from: mediaStatusData)
        XCTAssertEqual(decodedMediaStatus.type, "GET_STATUS")
        XCTAssertEqual(decodedMediaStatus.mediaSessionId, 5)
    }

    func testCastFramerConvenienceEncoders() throws {
        let text = "{\"type\":\"PING\"}"
        let framedString = CastV2Framer.encodeFramedString(text)
        XCTAssertEqual(framedString.count, 4 + text.utf8.count)

        var buffer = framedString
        let decoded = CastV2Framer.decodeFramedMessage(from: &buffer)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), text)

        let ping = CastPingCommand()
        let framedJSON = try CastV2Framer.encodeFramedJSON(ping)
        XCTAssertTrue(framedJSON.count > 4)

        var jsonBuffer = framedJSON
        let decodedJSONData = CastV2Framer.decodeFramedMessage(from: &jsonBuffer)
        XCTAssertNotNil(decodedJSONData)
        let decodedPing = try JSONDecoder().decode(CastPingCommand.self, from: decodedJSONData!)
        XCTAssertEqual(decodedPing.type, "PING")
    }

    func testAirPlayManagerDefaultValues() {
        let manager = AirPlayManager.shared
        // Default headless/CI environment
        XCTAssertFalse(manager.isAirPlayActive)
    }

    func testChromecastStreamBridgeVariousFormats() {
        let bridge = ChromecastStreamBridge()

        let formats: [(ext: String, mime: String, type: MediaType)] = [
            ("mp4", "video/mp4", .video),
            ("mov", "video/mp4", .video),
            ("mkv", "video/webm", .video),
            ("webm", "video/webm", .video),
            ("mp3", "audio/mpeg", .audio),
            ("flac", "audio/flac", .audio),
            ("aac", "audio/aac", .audio),
            ("m4a", "audio/aac", .audio),
            ("xyz", "video/mp4", .video)
        ]

        for item in formats {
            let media = MediaItem(
                title: "Sample \(item.ext)",
                filePath: "/media/sample.\(item.ext)",
                fileName: "sample.\(item.ext)",
                fileSize: 1024,
                duration: 60.0,
                mediaType: item.type,
                containerFormat: item.ext
            )
            let payload = bridge.generateCastPayload(for: media, serverPort: 8080, customHost: "192.168.1.100")
            XCTAssertEqual(payload.contentType, item.mime)
            XCTAssertEqual(payload.streamURL.absoluteString, "http://192.168.1.100:8080/stream/sample.\(item.ext)")
        }
    }

    func testChromecastServiceNotConnectedErrorHandling() async {
        let service = ChromecastService(isMockMode: false, fallbackToMockDevices: false)
        XCTAssertEqual(service.connectionState, .disconnected)

        do {
            try await service.play()
            XCTFail("play() must throw CastError.notConnected when disconnected")
        } catch let error as CastError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            try await service.pause()
            XCTFail("pause() must throw CastError.notConnected when disconnected")
        } catch let error as CastError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            try await service.stop()
            XCTFail("stop() must throw CastError.notConnected when disconnected")
        } catch let error as CastError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            try await service.seek(to: 10.0)
            XCTFail("seek() must throw CastError.notConnected when disconnected")
        } catch let error as CastError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        let payload = CastMediaPayload(
            streamURL: URL(string: "http://127.0.0.1:8080/stream/test.mp4")!,
            contentType: "video/mp4",
            title: "Test",
            duration: 100.0
        )
        do {
            try await service.loadMedia(payload: payload)
            XCTFail("loadMedia() must throw CastError.notConnected when disconnected")
        } catch let error as CastError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}


