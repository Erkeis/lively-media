// [Intent] Floating glass mini-player docking right above the tab bar with Studio Amber progress indicator
import SwiftUI
import CoreStorage
import PlaybackEngine

public struct MiniPlayerView: View {
    @ObservedObject public var coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator = .shared) {
        self.coordinator = coordinator
    }

    private var progress: Double {
        guard coordinator.duration > 0 else { return 0 }
        return max(0, min(coordinator.currentPosition / coordinator.duration, 1.0))
    }

    public var body: some View {
        guard coordinator.isMiniPlayerVisible, let item = coordinator.currentItem else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(spacing: 0) {
                // Studio Amber Top Progress Line
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.studioAmber)
                        .frame(width: geo.size.width * CGFloat(progress), height: 2)
                }
                .frame(height: 2)

                HStack(spacing: 14) {
                    // Artwork Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.obsidianElevated)
                        Image(systemName: item.mediaType == .video ? "film.fill" : "music.note")
                            .foregroundColor(.studioAmber)
                    }
                    .frame(width: 42, height: 42)

                    // Track Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.studioBody)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(item.artist ?? item.containerFormat.uppercased())
                            .font(.studioSecondary)
                            .foregroundColor(.studioSlate)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Play / Pause Toggle
                    Button(action: {
                        coordinator.togglePlayPause()
                    }) {
                        Image(systemName: coordinator.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }

                    // Next Track
                    Button(action: {
                        Task { await coordinator.next() }
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.studioSlate)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.obsidianSurface.opacity(0.95))
            }
            .background(Color.obsidianSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
            .onTapGesture {
                if item.mediaType == .video {
                    coordinator.isFullscreenVideoPresented = true
                } else {
                    coordinator.isFullscreenAudioPresented = true
                }
            }
        )
    }
}
