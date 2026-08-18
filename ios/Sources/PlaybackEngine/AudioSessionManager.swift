// [Intent] Concurrency-safe AVAudioSession manager handling background audio, route changes (AirPods disconnect), and interruptions (Calls/Siri)
import Foundation
import AVFoundation

public protocol AudioSessionManagerProtocol: Sendable {
    func configurePlaybackSession() throws
    func handleInterruption(notification: Notification, onPause: @escaping @Sendable () -> Void, onResume: @escaping @Sendable () -> Void)
    func handleRouteChange(notification: Notification, onPause: @escaping @Sendable () -> Void)
}

public final class AudioSessionManager: AudioSessionManagerProtocol, @unchecked Sendable {
    public static let shared = AudioSessionManager()

    public init() {}

    public func configurePlaybackSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio)
        try session.setActive(true)
        #endif
    }

    public func handleInterruption(
        notification: Notification,
        onPause: @escaping @Sendable () -> Void,
        onResume: @escaping @Sendable () -> Void
    ) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began (e.g. incoming phone call or Siri)
            onPause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    onResume()
                }
            }
        @unknown default:
            break
        }
        #endif
    }

    public func handleRouteChange(
        notification: Notification,
        onPause: @escaping @Sendable () -> Void
    ) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // e.g. AirPods or Wired headphones were disconnected -> auto pause to prevent blasting speakers
            if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs {
                    if output.portType == .headphones || output.portType == .bluetoothA2DP || output.portType == .airPlay {
                        onPause()
                        break
                    }
                }
            }
        default:
            break
        }
        #endif
    }
}
