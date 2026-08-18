// [Intent] Unit tests verifying PodcastFeedParser XML parsing of podcast channel and episode enclosures
import XCTest
@testable import PodcastEngine

final class PodcastEngineTests: XCTestCase {
    func testPodcastFeedParsing() throws {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
            <channel>
                <title>Obsidian Soundscapes</title>
                <description>Professional mastering podcasts</description>
                <itunes:author>Acoustic Studio</itunes:author>
                <item>
                    <title>Episode 1: Pure Analog Warmth</title>
                    <description>A deep dive into warm mastering tones</description>
                    <enclosure url="https://example.com/ep1.mp3" length="12345678" type="audio/mpeg" />
                </item>
                <item>
                    <title>Episode 2: Lossless FLAC Dynamic Range</title>
                    <description>Exploring high bit-depth FLAC audio</description>
                    <enclosure url="https://example.com/ep2.flac" length="45678901" type="audio/flac" />
                </item>
            </channel>
        </rss>
        """

        let parser = PodcastFeedParser()
        let channel = try parser.parseFeed(data: sampleXML.data(using: .utf8)!, feedURL: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(channel.title, "Obsidian Soundscapes")
        XCTAssertEqual(channel.author, "Acoustic Studio")
        XCTAssertEqual(channel.episodes.count, 2)
        XCTAssertEqual(channel.episodes[0].title, "Episode 1: Pure Analog Warmth")
        XCTAssertEqual(channel.episodes[0].audioURL.absoluteString, "https://example.com/ep1.mp3")
        XCTAssertEqual(channel.episodes[1].title, "Episode 2: Lossless FLAC Dynamic Range")
        XCTAssertEqual(channel.episodes[1].audioURL.absoluteString, "https://example.com/ep2.flac")
    }
}
