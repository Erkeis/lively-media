// [Intent] Auto-scrolling synchronized lyrics view with karaoke active line highlight in Studio Amber
import SwiftUI

public struct LyricLine: Identifiable, Hashable {
    public let id = UUID()
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public struct SyncedLyricsView: View {
    public let lyrics: [LyricLine]
    public let currentPosition: TimeInterval
    public let onSeek: (TimeInterval) -> Void

    public init(
        lyrics: [LyricLine],
        currentPosition: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.lyrics = lyrics
        self.currentPosition = currentPosition
        self.onSeek = onSeek
    }

    private var activeLineIndex: Int {
        for (index, line) in lyrics.enumerated().reversed() {
            if currentPosition >= line.time {
                return index
            }
        }
        return 0
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeLineIndex
                        Text(line.text)
                            .font(isActive ? .studioSection : .studioBody)
                            .foregroundColor(isActive ? .studioAmber : .studioSlate.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .scaleEffect(isActive ? 1.05 : 0.95)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
                            .id(index)
                            .onTapGesture {
                                onSeek(line.time)
                            }
                    }
                }
                .padding(.vertical, 80)
            }
            .onChange(of: activeLineIndex) { _, newIndex in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}
