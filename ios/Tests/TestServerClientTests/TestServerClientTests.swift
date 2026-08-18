// [Intent] Unit tests verifying Linux Test Server URL formatting, WebDAV listings, and Range responses
import XCTest
@testable import TestServerClient

final class TestServerClientTests: XCTestCase {
    func testServerConfigURLFormatting() {
        let config = ServerConfig(host: "192.168.1.50", streamPort: 8081, webDAVPort: 8082, podcastPort: 8083)

        XCTAssertEqual(config.streamBaseURL.absoluteString, "http://192.168.1.50:8081/media")
        XCTAssertEqual(config.webDAVBaseURL.absoluteString, "http://192.168.1.50:8082")
        XCTAssertEqual(config.podcastFeedURL.absoluteString, "http://192.168.1.50:8083/feed.xml")
    }

    func testWebDAVDirectoryListing() async throws {
        let client = WebDAVClient()
        let items = try await client.listDirectory(at: "/")

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].name, "sample_1080p_h264.mp4")
        XCTAssertEqual(items[2].name, "sample_hires.flac")
    }

    func testMockPodcastFeedFetching() async throws {
        let client = MockPodcastClient()
        let episodes = try await client.fetchFeed(feedURL: URL(string: "http://127.0.0.1:8083/feed.xml")!)

        XCTAssertEqual(episodes.count, 2)
        XCTAssertTrue(episodes[0].title.contains("Episode 1"))
        XCTAssertTrue(episodes[1].title.contains("Episode 2"))
    }
}
