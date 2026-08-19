// [Intent] Models representing AirPlay and Google Cast targets, device metadata, and connection states
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

public struct CastDevice: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let type: CastTargetType
    public let ipAddress: String?
    public let port: UInt16
    public let modelName: String?
    public let capabilities: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: CastTargetType,
        ipAddress: String? = nil,
        port: UInt16 = 8009,
        modelName: String? = nil,
        capabilities: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.ipAddress = ipAddress
        self.port = port
        self.modelName = modelName
        self.capabilities = capabilities
    }
}
