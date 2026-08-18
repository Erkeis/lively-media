// [Intent] Fullscreen Studio Audio Player modal view with rotating artwork, waveform scrubber, lyrics, and EQ integration
import SwiftUI
import CoreStorage
import PlaybackEngine

public struct AudioPlayerModalView: View {
    @ObservedObject public var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var activeTab: Int = 0 // 0: Artwork, 1: Lyrics, 2: Equalizer
    @State private var mockLyrics: [LyricLine] = [
        LyricLine(time: 0.0, text: "Welcome to Obsidian Studio"),
        LyricLine(time: 15.0, text: "High-fidelity lossless sound"),
        LyricLine(time: 45.0, text: "Master audio console quality"),
        LyricLine(time: 80.0, text: "Universal playback for all formats")
    ]

    public init(coordinator: PlaybackCoordinator = .shared) {
        self.coordinator = coordinator
    }

    public var body: some View {
        guard let item = coordinator.currentItem else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ZStack {
                Color.obsidianBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    // 1. Top Navigation Bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text(item.album ?? "PLAYING FROM LIBRARY")
                                .font(.studioMonoSpec)
                                .foregroundColor(.studioSlate)
                            Text(item.containerFormat.uppercased() + " • LOSSLESS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.studioAmber)
                        }

                        Spacer()

                        // Tab / Mode Picker (Art, Lyrics, EQ)
                        HStack(spacing: 8) {
                            Button(action: { activeTab = activeTab == 1 ? 0 : 1 }) {
                                Image(systemName: "quote.bubble.fill")
                                    .foregroundColor(activeTab == 1 ? .studioAmber : .studioSlate)
                            }
                            Button(action: { activeTab = activeTab == 2 ? 0 : 2 }) {
                                Image(systemName: "slider.vertical.3")
                                    .foregroundColor(activeTab == 2 ? .studioAmber : .studioSlate)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // 2. Middle Presentation (Artwork vs Lyrics vs EQ)
                    if activeTab == 0 {
                        // Artwork with subtle amber ambient shadow
                        ZStack {
                            Circle()
                                .fill(Color.studioAmber.opacity(0.12))
                                .frame(width: 260, height: 260)
                                .blur(radius: 40)

                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.obsidianElevated)
                                .frame(width: 240, height: 240)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 80))
                                        .foregroundColor(.studioAmber)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.obsidianBorder, lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.6), radius: 20, y: 10)
                        }
                        .frame(height: 280)
                    } else if activeTab == 1 {
                        SyncedLyricsView(
                            lyrics: mockLyrics,
                            currentPosition: coordinator.currentPosition,
                            onSeek: { pos in coordinator.seek(to: pos) }
                        )
                        .frame(height: 280)
                    } else {
                        EqualizerView()
                            .frame(height: 280)
                    }

                    Spacer()

                    // 3. Track Title & Artist
                    VStack(spacing: 6) {
                        Text(item.title)
                            .font(.studioLargeTitle)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(item.artist ?? "Unknown Artist")
                            .font(.studioSection)
                            .foregroundColor(.studioSlate)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)

                    // 4. Waveform Amplitude Scrubber
                    VStack(spacing: 8) {
                        WaveformScrubberView(
                            waveformSamples: [],
                            currentPosition: coordinator.currentPosition,
                            duration: coordinator.duration,
                            onSeek: { targetPos in coordinator.seek(to: targetPos) }
                        )

                        // Timecode Displays (SF Mono - zero jitter)
                        HStack {
                            Text(formatTime(coordinator.currentPosition))
                                .font(.studioMonoTime)
                                .foregroundColor(.studioSlate)
                            Spacer()
                            Text("-" + formatTime(max(0, coordinator.duration - coordinator.currentPosition)))
                                .font(.studioMonoTime)
                                .foregroundColor(.studioSlate)
                        }
                    }
                    .padding(.horizontal, 24)

                    // 5. Studio Playback Controls
                    HStack(spacing: 28) {
                        Button(action: { Task { await coordinator.previous() } }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }

                        Button(action: { coordinator.seek(by: -10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 22))
                                .foregroundColor(.studioSlate)
                        }

                        // Play/Pause Hero Button
                        Button(action: { coordinator.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.studioAmber)
                                    .frame(width: 68, height: 68)
                                    .shadow(color: Color.studioAmber.opacity(0.35), radius: 16)

                                Image(systemName: coordinator.state == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.obsidianBackground)
                            }
                        }

                        Button(action: { coordinator.seek(by: 10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 22))
                                .foregroundColor(.studioSlate)
                        }

                        Button(action: { Task { await coordinator.next() } }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 12)

                    // 6. Bottom Volume & Speed Options
                    HStack(spacing: 16) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.studioSlate)

                        Slider(
                            value: Binding(
                                get: { Double(coordinator.volume) },
                                set: { coordinator.volume = Float($0) }
                            ),
                            in: 0...1
                        )
                        .tint(.studioAmber)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.studioSlate)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
