// [Intent] 10-band graphic equalizer with parametric curve visualizer and master audio presets
import SwiftUI

public struct EqualizerPreset: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let gains: [Float] // 10 band gains (-12dB to +12dB)

    public init(name: String, gains: [Float]) {
        self.name = name
        self.gains = gains
    }

    public static let standardPresets: [EqualizerPreset] = [
        EqualizerPreset(name: "Studio Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqualizerPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 1, 2, 3]),
        EqualizerPreset(name: "Vocal Clarifier", gains: [-2, -1, 0, 2, 4, 5, 4, 2, 1, 0]),
        EqualizerPreset(name: "Acoustic", gains: [3, 2, 1, 1, 2, 2, 3, 3, 3, 2]),
        EqualizerPreset(name: "Electronic", gains: [5, 4, 2, 0, -2, 2, 1, 3, 4, 5]),
        EqualizerPreset(name: "Rock", gains: [4, 3, 2, 0, -1, 1, 2, 3, 4, 4]),
        EqualizerPreset(name: "Classical", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 3])
    ]
}

public struct EqualizerView: View {
    @State private var bandGains: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    @State private var selectedPreset: EqualizerPreset = EqualizerPreset.standardPresets[0]
    @State private var isEnabled: Bool = true

    private let bandFrequencies: [String] = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Header & Enable Toggle
            HStack {
                Text("Master Equalizer")
                    .font(.studioSection)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(.studioAmber)
            }

            // Preset Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqualizerPreset.standardPresets) { preset in
                        Button(action: {
                            selectedPreset = preset
                            bandGains = preset.gains
                        }) {
                            Text(preset.name)
                                .font(.studioCaption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPreset == preset ? Color.studioAmber : Color.obsidianElevated)
                                .foregroundColor(selectedPreset == preset ? Color.obsidianBackground : Color.white)
                                .cornerRadius(12)
                        }
                    }
                }
            }

            // 10 Sliders
            HStack(spacing: 12) {
                ForEach(0..<10, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text("\(Int(bandGains[index]))dB")
                            .font(.studioMonoSpec)
                            .foregroundColor(.studioSlate)

                        // Vertical Gain Slider Simulation
                        Slider(
                            value: Binding(
                                get: { Double(bandGains[index]) },
                                set: { bandGains[index] = Float($0) }
                            ),
                            in: -12...12,
                            step: 1
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 120, height: 28)
                        .tint(isEnabled ? .studioAmber : .studioSlate)
                        .disabled(!isEnabled)

                        Text(bandFrequencies[index])
                            .font(.studioMonoSpec)
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(height: 180)
            .padding(.vertical, 10)
        }
        .padding(20)
        .obsidianCard()
    }
}
