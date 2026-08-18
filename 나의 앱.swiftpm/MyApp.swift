import SwiftUI
import AVFoundation

@main
struct MyApp: App {
    @StateObject private var coordinator = PlaybackCoordinator.shared

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)
        }
    }
}
