// [Intent] Interactive 100-bar waveform amplitude scrubber with drag gesture seeking and haptic feedback
import SwiftUI
import CoreStorage

public struct WaveformScrubberView: View {
    public let waveformSamples: [Float]
    public let currentPosition: TimeInterval
    public let duration: TimeInterval
    public let onSeek: (TimeInterval) -> Void

    @State private var isDragging: Bool = false
    @State private var dragPosition: TimeInterval = 0.0

    public init(
        waveformSamples: [Float],
        currentPosition: TimeInterval,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.waveformSamples = waveformSamples.isEmpty ? Array(repeating: 0.25, count: 60) : waveformSamples
        self.currentPosition = currentPosition
        self.duration = duration
        self.onSeek = onSeek
    }

    private var activeProgress: Double {
        guard duration > 0 else { return 0 }
        let pos = isDragging ? dragPosition : currentPosition
        return max(0, min(pos / duration, 1.0))
    }

    public var body: some View {
        GeometryReader { geo in
            let barWidth = max(2.0, (geo.size.width / CGFloat(waveformSamples.count)) - 2.0)
            let totalBars = waveformSamples.count

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<totalBars, id: \.self) { index in
                    let sampleHeight = max(6.0, CGFloat(waveformSamples[index]) * geo.size.height)
                    let barProgress = Double(index) / Double(totalBars)
                    let isActive = barProgress <= activeProgress

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? Color.studioAmber : Color.obsidianBorder)
                        .frame(width: barWidth, height: sampleHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                        dragPosition = fraction * duration
                        triggerHapticFeedback()
                    }
                    .onEnded { value in
                        let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                        let targetPos = fraction * duration
                        isDragging = false
                        onSeek(targetPos)
                    }
            )
        }
        .frame(height: 50)
    }

    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.5)
        #endif
    }
}
