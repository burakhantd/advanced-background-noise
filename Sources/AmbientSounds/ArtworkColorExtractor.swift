import AppKit
import Foundation

struct ArtworkAccent: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var perceivedLuminance: Double {
        (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
    }

    func lifted(toMinimumLuminance minimum: Double) -> ArtworkAccent {
        let target = min(max(minimum, 0), 1)
        let luminance = perceivedLuminance
        guard luminance < target, luminance < 1 else { return self }
        let whiteMix = (target - luminance) / (1 - luminance)
        return ArtworkAccent(
            red: red + ((1 - red) * whiteMix),
            green: green + ((1 - green) * whiteMix),
            blue: blue + ((1 - blue) * whiteMix)
        )
    }
}

enum ArtworkColorExtractor {
    private struct Bucket {
        var score = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var samples = 0.0
    }

   static func accent(from url: URL) async -> ArtworkAccent? {
        let rawData: Data?
        if url.isFileURL {
            rawData = try? Data(contentsOf: url)
        } else {
            rawData = (try? await URLSession.shared.data(from: url))?.0
        }
        guard
            let data = rawData,
            let image = NSImage(data: data),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let dimension = 32
        let bytesPerRow = dimension * 4
        var pixels = [UInt8](repeating: 0, count: dimension * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        return dominantAccent(rgba: pixels)
    }

    static func dominantAccent(rgba pixels: [UInt8]) -> ArtworkAccent? {
        guard pixels.count >= 4 else { return nil }
        var buckets: [Int: Bucket] = [:]

        for index in stride(from: 0, to: pixels.count - 3, by: 4) {
            guard pixels[index + 3] > 160 else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let luminance = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
            guard luminance > 0.07, luminance < 0.94 else { continue }

            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
            let score = 0.08 + pow(saturation, 1.35) * 2.4
            let redBin = min(Int(red * 5), 4)
            let greenBin = min(Int(green * 5), 4)
            let blueBin = min(Int(blue * 5), 4)
            let key = (redBin << 8) | (greenBin << 4) | blueBin
            var bucket = buckets[key, default: Bucket()]
            bucket.score += score
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            bucket.samples += 1
            buckets[key] = bucket
        }

        guard let winner = buckets.values.max(by: { $0.score < $1.score }), winner.samples > 0 else {
            return nil
        }
        return ArtworkAccent(
            red: winner.red / winner.samples,
            green: winner.green / winner.samples,
            blue: winner.blue / winner.samples
        )
    }
}
