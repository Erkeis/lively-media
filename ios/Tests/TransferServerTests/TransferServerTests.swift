// [Intent] Unit tests verifying WebAssets HTML markup, QR Code URL formatting, and transfer server configuration
import XCTest
@testable import TransferServer

final class TransferServerTests: XCTestCase {
    func testWebAssetsContainsRequiredUIElements() {
        let html = WebAssets.indexHTML
        XCTAssertTrue(html.contains("Obsidian Studio"))
        XCTAssertTrue(html.contains("dropZone"))
        XCTAssertTrue(html.contains("/api/upload"))
        XCTAssertTrue(html.contains("/api/files"))
        XCTAssertTrue(html.contains("progressBar"))
    }

    func testQRCodePayloadWithCustomHost() {
        let payload = QRCodePayload(port: 8080, customHost: "192.168.1.120")
        XCTAssertEqual(payload.connectionURLString, "http://192.168.1.120:8080")
    }

    func testQRCodePayloadDefaultPort() {
        let payload = QRCodePayload()
        XCTAssertEqual(payload.port, 8080)
        XCTAssertTrue(payload.connectionURLString.hasPrefix("http://"))
    }

    func testWebTransferServerInitialization() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = WebTransferServer(port: 8088, targetDirectory: tempDir)
        XCTAssertNotNil(server)
    }
}
