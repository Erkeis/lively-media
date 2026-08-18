// [Intent] Model representing a detected media stream intercepted from WKWebView
import Foundation

public struct DetectedStreamItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let streamURL: URL
    public let pageURL: URL
    public let title: String
    public let containerFormat: String
    public let isLiveHLS: Bool

    public init(
        id: String = UUID().uuidString,
        streamURL: URL,
        pageURL: URL,
        title: String,
        containerFormat: String,
        isLiveHLS: Bool = false
    ) {
        self.id = id
        self.streamURL = streamURL
        self.pageURL = pageURL
        self.title = title
        self.containerFormat = containerFormat.lowercased()
        self.isLiveHLS = isLiveHLS
    }
}
