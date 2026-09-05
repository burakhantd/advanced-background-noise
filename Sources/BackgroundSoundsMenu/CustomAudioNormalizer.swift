import Accelerate
import AVFoundation
import Foundation

struct AudioNormalizationResult: Equatable, Sendable {
    let measuredRMSDecibels: Double
    let measuredPeakDecibels: Double
    let gainDecibels: Double
    let leadingSilenceDuration: TimeInterval
}

enum CustomAudioNormalizer {
    static let targetRMSDecibels = -23.0
    static let peakCeilingDecibels = -1.0
    static let maximumBoostDecibels = 12.0
    static let maximumCutDecibels = -18.0

    static func gainDecibels(measuredRMS: Double, measuredPeak: Double) -> Double {
        let levelMatch = targetRMSDecibels - measuredRMS
        let clippingSafeBoost = peakCeilingDecibels - measuredPeak
        return min(max(min(levelMatch, clippingSafeBoost), maximumCutDecibels), maximumBoostDecibels)
    }

    static func analyze(url: URL) throws -> AudioNormalizationResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let capacity: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var sumOfSquares = 0.0
        var sampleCount: UInt64 = 0
        var absolutePeak: Float = 0
        var framesProcessed: UInt64 = 0
        var firstAudibleFrame: UInt64?
        let audibleThreshold = pow(10.0, -45.0 / 20.0)

        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let frameCount = AVAudioFrameCount(min(AVAudioFramePosition(capacity), remaining))
            try file.read(into: buffer, frameCount: frameCount)
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }

            for channel in 0..<Int(format.channelCount) {
                var channelSquares: Float = 0
                var channelPeak: Float = 0
                vDSP_svesq(channels[channel], 1, &channelSquares, vDSP_Length(buffer.frameLength))
                vDSP_maxmgv(channels[channel], 1, &channelPeak, vDSP_Length(buffer.frameLength))
                sumOfSquares += Double(channelSquares)
                absolutePeak = max(absolutePeak, channelPeak)
                sampleCount += UInt64(buffer.frameLength)
            }

            if firstAudibleFrame == nil {
                let windowSize = 1_024
                for offset in stride(from: 0, to: Int(buffer.frameLength), by: windowSize) {
                    let count = min(windowSize, Int(buffer.frameLength) - offset)
                    var windowSquares = 0.0
                    for channel in 0..<Int(format.channelCount) {
                        var squares: Float = 0
                        vDSP_svesq(channels[channel] + offset, 1, &squares, vDSP_Length(count))
                        windowSquares += Double(squares)
                    }
                    let windowRMS = sqrt(windowSquares / Double(count * Int(format.channelCount)))
                    if windowRMS >= audibleThreshold {
                        firstAudibleFrame = framesProcessed + UInt64(offset)
                        break
                    }
                }
            }
            framesProcessed += UInt64(buffer.frameLength)
        }

        guard sampleCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        let rmsDB = 20 * log10(max(rms, 0.000_000_001))
        let peakDB = 20 * log10(max(Double(absolutePeak), 0.000_000_001))
        return AudioNormalizationResult(
            measuredRMSDecibels: rmsDB,
            measuredPeakDecibels: peakDB,
            gainDecibels: gainDecibels(measuredRMS: rmsDB, measuredPeak: peakDB),
            leadingSilenceDuration: Double(firstAudibleFrame ?? 0) / format.sampleRate
        )
    }
}
