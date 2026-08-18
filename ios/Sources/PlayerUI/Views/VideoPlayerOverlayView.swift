// [Intent] 120Hz ProMotion gesture video player with vertical brightness/volume split HUD and double-tap skip ripples
import SwiftUI
import CoreStorage
import PlaybackEngine

public struct VideoPlayerOverlayView: View {
    @ObservedObject public var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var areControlsVisible: Bool = true
    @State private var brightnessHUD: Float = 0.5
    @State private var volumeHUD: Float = 0.8
    @State private var showBrightnessHUD: Bool = false
    @State private var showVolumeHUD: Bool = false
    @State private var showDoubleTapRipple: Bool = false
    @State private var doubleTapIsForward: Bool = true
    @State private var controlsTimer: Timer?

    public init(coordinator: PlaybackCoordinator? = nil) {
        self.coordinator = coordinator ?? PlaybackCoordinator.shared
    }

    public var body: some View {
        guard let item = coordinator.currentItem else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Video Surface Simulation
                ZStack {
                    Image(systemName: "film")
                        .font(.system(size: 100))
                        .foregroundColor(.obsidianBorder)

                    // Double-tap 10s Skip Ripple Animation
                    if showDoubleTapRipple {
                        HStack {
                            if !doubleTapIsForward {
                                VStack(spacing: 8) {
                                    Image(systemName: "gobackward.10")
                                        .font(.system(size: 44))
                                    Text("10s")
                                        .font(.studioMonoSpec)
                                }
                                .foregroundColor(.white)
                                .padding(24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .transition(.scale.combined(with: .opacity))
                            }

                            Spacer()

                            if doubleTapIsForward {
                                VStack(spacing: 8) {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 44))
                                    Text("10s")
                                        .font(.studioMonoSpec)
                                }
                                .foregroundColor(.white)
                                .padding(24)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 60)
                    }

                    // Brightness & Volume Vertical HUD Indicators
                    HStack {
                        if showBrightnessHUD {
                            VStack(spacing: 8) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundColor(.studioAmber)
                                ProgressView(value: Double(brightnessHUD), total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .studioAmber))
                                    .frame(width: 80)
                                    .rotationEffect(.degrees(-90))
                                    .frame(height: 80)
                                Text("\(Int(brightnessHUD * 100))%")
                                    .font(.studioMonoSpec)
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(Color.obsidianElevated.opacity(0.85))
                            .cornerRadius(16)
                        }

                        Spacer()

                        if showVolumeHUD {
                            VStack(spacing: 8) {
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundColor(.studioAmber)
                                ProgressView(value: Double(volumeHUD), total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .studioAmber))
                                    .frame(width: 80)
                                    .rotationEffect(.degrees(-90))
                                    .frame(height: 80)
                                Text("\(Int(volumeHUD * 100))%")
                                    .font(.studioMonoSpec)
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(Color.obsidianElevated.opacity(0.85))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    triggerDoubleTapSkip(isForward: location.x > 200)
                }
                .onTapGesture(count: 1) {
                    toggleControlsVisibility()
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            handleVerticalPanGesture(value: value)
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                withAnimation {
                                    showBrightnessHUD = false
                                    showVolumeHUD = false
                                }
                            }
                        }
                )

                // 2. Overlay Controls (Top and Bottom HUD)
                if areControlsVisible {
                    VStack {
                        // Top Bar
                        HStack(spacing: 16) {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }

                            Text(item.title)
                                .font(.studioBody)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            // Codec & HDR Badge
                            Text("HEVC • 1080p")
                                .font(.studioMonoSpec)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.obsidianElevated)
                                .cornerRadius(6)
                                .foregroundColor(.studioAmber)

                            // PiP Button
                            Button(action: {}) {
                                Image(systemName: "pip.enter")
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        Spacer()

                        // Center Play/Pause Overlay
                        Button(action: { coordinator.togglePlayPause() }) {
                            Image(systemName: coordinator.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .padding(24)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }

                        Spacer()

                        // Bottom Scrubber Bar & Controls
                        VStack(spacing: 12) {
                            // Scrubber
                            HStack(spacing: 14) {
                                Text(formatTime(coordinator.currentPosition))
                                    .font(.studioMonoTime)
                                    .foregroundColor(.white)

                                Slider(
                                    value: Binding(
                                        get: { coordinator.currentPosition },
                                        set: { coordinator.seek(to: $0) }
                                    ),
                                    in: 0...max(1.0, coordinator.duration)
                                )
                                .tint(.studioAmber)

                                Text("-" + formatTime(max(0, coordinator.duration - coordinator.currentPosition)))
                                    .font(.studioMonoTime)
                                    .foregroundColor(.studioSlate)
                            }

                            // Secondary Options (Subtitles, Aspect Ratio, Speed)
                            HStack {
                                Button("Subtitles: [KOR]") {}
                                    .font(.studioCaption)
                                    .foregroundColor(.studioAmber)

                                Spacer()

                                Button("1.0x") {
                                    coordinator.playbackRate = coordinator.playbackRate == 1.0 ? 1.5 : 1.0
                                }
                                .font(.studioMonoSpec)
                                .foregroundColor(.white)
                            }
                        }
                        .padding(20)
                        .background(Color.black.opacity(0.75))
                    }
                    .transition(.opacity)
                }
            }
        )
    }

    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible.toggle()
        }
    }

    private func handleVerticalPanGesture(value: DragGesture.Value) {
        let isLeftScreen = value.startLocation.x < 180
        let delta = Float(-value.translation.height / 300.0)

        if isLeftScreen {
            brightnessHUD = max(0, min(1, brightnessHUD + delta * 0.05))
            showBrightnessHUD = true
        } else {
            volumeHUD = max(0, min(1, volumeHUD + delta * 0.05))
            coordinator.volume = volumeHUD
            showVolumeHUD = true
        }
    }

    private func triggerDoubleTapSkip(isForward: Bool) {
        doubleTapIsForward = isForward
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            showDoubleTapRipple = true
        }
        coordinator.seek(by: isForward ? 10 : -10)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                showDoubleTapRipple = false
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
