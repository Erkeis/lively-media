// [Intent] Models representing AirPlay and Google Cast targets and connection states
import Foundation

public enum CastTargetType: String, Sendable, Codable {
    case localDevice
    case airPlay
    case chromecast
}

public enum CastConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(deviceName: String)
    case failed(String)
}

public struct CastDevice: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let type: CastTargetType
    public let ipAddress: String?

    public init(id: String = UUID().uuidString, name: String, type: CastTargetType, ipAddress: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.ipAddress = ipAddress
    }
}
