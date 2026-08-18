// [Intent] Generates 100-bar normalized amplitude waveform arrays for instant scrubber UI rendering
import Foundation
import AVFoundation

public protocol WaveformGeneratorProtocol: Sendable {
    func generateWaveform(url: URL, sampleCount: Int) async throws -> [Float]
    func serializeWaveform(_ samples: [Float]) -> Data
    func deserializeWaveform(_ data: Data) -> [Float]
}

public final class WaveformGenerator: WaveformGeneratorProtocol {
    public init() {}

    public func generateWaveform(url: URL, sampleCount: Int = 100) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return Array(repeating: 0.1, count: sampleCount)
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(readerOutput)
        reader.startReading()

        var sampleData = [Float]()
        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                break
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var rawBytes = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &rawBytes)

            for sample in rawBytes {
                sampleData.append(abs(Float(sample)) / Float(Int16.max))
            }
        }

        guard !sampleData.isEmpty else {
            return Array(repeating: 0.2, count: sampleCount)
        }

        // Downsample into fixed `sampleCount` bins
        let binSize = max(1, sampleData.count / sampleCount)
        var result = [Float]()
        for i in 0..<sampleCount {
            let start = i * binSize
            let end = min(start + binSize, sampleData.count)
            guard start < end else {
                result.append(0.1)
                continue
            }
            let slice = sampleData[start..<end]
            let avg = slice.reduce(0, +) / Float(slice.count)
            result.append(min(1.0, max(0.05, avg)))
        }

        // Normalize to peak 1.0
        let maxVal = result.max() ?? 1.0
        if maxVal > 0 {
            return result.map { $0 / maxVal }
        }
        return result
    }

    public func serializeWaveform(_ samples: [Float]) -> Data {
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public func deserializeWaveform(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
