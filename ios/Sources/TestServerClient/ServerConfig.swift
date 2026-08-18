// [Intent] Linux test server endpoint configuration supporting both local LAN and Tailscale mesh VPN
import Foundation

public struct ServerConfig: Sendable, Codable {
    public var host: String
    public var streamPort: UInt16
    public var webDAVPort: UInt16
    public var podcastPort: UInt16
    public var webDAVUser: String?
    public var webDAVPass: String?

    public init(
        host: String = "127.0.0.1",
        streamPort: UInt16 = 8081,
        webDAVPort: UInt16 = 8082,
        podcastPort: UInt16 = 8083,
        webDAVUser: String? = "testuser",
        webDAVPass: String? = "testpassword"
    ) {
        self.host = host
        self.streamPort = streamPort
        self.webDAVPort = webDAVPort
        self.podcastPort = podcastPort
        self.webDAVUser = webDAVUser
        self.webDAVPass = webDAVPass
    }

    public var streamBaseURL: URL {
        URL(string: "http://\(host):\(streamPort)/media")!
    }

    public var webDAVBaseURL: URL {
        URL(string: "http://\(host):\(webDAVPort)")!
    }

    public var podcastFeedURL: URL {
        URL(string: "http://\(host):\(podcastPort)/feed.xml")!
    }
}
