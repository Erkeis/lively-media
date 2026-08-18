// [Intent] AirPlay 2 route manager monitoring route changes and active Apple TV / HomePod destinations
import Foundation
import AVFoundation
import MediaPlayer

public protocol AirPlayManagerProtocol: Sendable {
    var isAirPlayActive: Bool { get }
    var activeAirPlayDeviceName: String? { get }
}

public final class AirPlayManager: AirPlayManagerProtocol, @unchecked Sendable {
    public static let shared = AirPlayManager()

    public var isAirPlayActive: Bool {
        #if os(iOS)
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        return currentRoute.outputs.contains { $0.portType == .airPlay }
        #else
        return false
        #endif
    }

    public var activeAirPlayDeviceName: String? {
        #if os(iOS)
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        return currentRoute.outputs.first(where: { $0.portType == .airPlay })?.portName
        #else
        return nil
        #endif
    }

    public init() {}
}
