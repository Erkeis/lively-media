// [Intent] Unit tests verifying MediaSnifferScript JavaScript injection and DetectedStreamItem modeling
import XCTest
@testable import WebSnifferEngine

final class WebSnifferEngineTests: XCTestCase {
    func testMediaSnifferScriptContent() {
        let script = MediaSnifferScript.sourceJavaScript
        XCTAssertTrue(script.contains("mediaSniffer"))
        XCTAssertTrue(script.contains(".m3u8"))
        XCTAssertTrue(script.contains(".mp4"))
        XCTAssertTrue(script.contains("MutationObserver"))
    }

    func testDetectedStreamItemInitialization() {
        let streamURL = URL(string: "https://example.com/live/playlist.m3u8")!
        let pageURL = URL(string: "https://example.com/watch")!

        let item = DetectedStreamItem(
            streamURL: streamURL,
            pageURL: pageURL,
            title: "Live Concert Stream",
            containerFormat: "m3u8",
            isLiveHLS: true
        )

        XCTAssertEqual(item.title, "Live Concert Stream")
        XCTAssertEqual(item.containerFormat, "m3u8")
        XCTAssertTrue(item.isLiveHLS)
    }
}
