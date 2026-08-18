// [Intent] RSS 2.0 / iTunes XML podcast feed parser extracting episode enclosures and channel metadata
import Foundation

public protocol PodcastFeedParserProtocol: Sendable {
    func parseFeed(data: Data, feedURL: URL) throws -> PodcastChannel
}

public final class PodcastFeedParser: NSObject, PodcastFeedParserProtocol, XMLParserDelegate, @unchecked Sendable {
    private var channelTitle: String = ""
    private var channelDesc: String = ""
    private var channelAuthor: String = ""
    private var channelArtworkURL: URL?

    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentDesc: String = ""
    private var currentEnclosureURL: URL?
    private var currentDuration: TimeInterval = 0.0
    private var isInsideItem: Bool = false

    private var parsedEpisodes: [PodcastChannelItem] = []

    public override init() {
        super.init()
    }

    public func parseFeed(data: Data, feedURL: URL) throws -> PodcastChannel {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        return PodcastChannel(
            title: channelTitle.isEmpty ? "Podcast Feed" : channelTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            channelDescription: channelDesc.trimmingCharacters(in: .whitespacesAndNewlines),
            author: channelAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
            feedURL: feedURL,
            artworkURL: channelArtworkURL,
            episodes: parsedEpisodes
        )
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        if elementName.lowercased() == "item" {
            isInsideItem = true
            currentTitle = ""
            currentDesc = ""
            currentEnclosureURL = nil
            currentDuration = 0.0
        } else if elementName.lowercased() == "enclosure", let urlStr = attributeDict["url"], let url = URL(string: urlStr) {
            currentEnclosureURL = url
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideItem {
            if currentElement.lowercased() == "title" {
                currentTitle += string
            } else if currentElement.lowercased() == "description" {
                currentDesc += string
            }
        } else {
            if currentElement.lowercased() == "title" {
                channelTitle += string
            } else if currentElement.lowercased() == "description" {
                channelDesc += string
            } else if currentElement.lowercased() == "itunes:author" || currentElement.lowercased() == "author" {
                channelAuthor += string
            }
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            isInsideItem = false
            if let audioURL = currentEnclosureURL {
                let episode = PodcastChannelItem(
                    title: currentTitle.isEmpty ? "Episode" : currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    episodeDescription: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    audioURL: audioURL,
                    duration: currentDuration
                )
                parsedEpisodes.append(episode)
            }
        }
    }
}
