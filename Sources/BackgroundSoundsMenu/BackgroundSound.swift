import AVFoundation
import Foundation

struct BackgroundSound: Identifiable, Hashable {
    let group: Int
    let name: String
    let title: String
    let symbol: String

    var id: Int { group }

    static let all: [BackgroundSound] = [
        .init(group: 1, name: "PinkNoise", title: "Balanced Noise", symbol: "waveform"),
        .init(group: 2, name: "WhiteNoise", title: "Bright Noise", symbol: "sparkles"),
        .init(group: 3, name: "BrownNoise", title: "Dark Noise", symbol: "waveform.path"),
        .init(group: 4, name: "Ocean", title: "Ocean", symbol: "water.waves"),
        .init(group: 5, name: "Rain", title: "Rain", symbol: "cloud.rain.fill"),
        .init(group: 6, name: "Stream", title: "Stream", symbol: "drop.fill"),
        .init(group: 7, name: "Night", title: "Night", symbol: "moon.stars.fill"),
        .init(group: 8, name: "Fire", title: "Fire", symbol: "flame.fill"),
        .init(group: 9, name: "Babble", title: "Babble", symbol: "person.2.wave.2.fill"),
        .init(group: 10, name: "Steam", title: "Steam", symbol: "wind"),
        .init(group: 11, name: "Airplane", title: "Airplane", symbol: "airplane"),
        .init(group: 12, name: "Boat", title: "Boat", symbol: "ferry.fill"),
        .init(group: 13, name: "Bus", title: "Bus", symbol: "bus.fill"),
        .init(group: 14, name: "Train", title: "Train", symbol: "tram.fill"),
        .init(group: 15, name: "RainOnRoof", title: "Rain on Roof", symbol: "house.and.flag.fill"),
        .init(group: 16, name: "QuietNight", title: "Quiet Night", symbol: "moon.zzz.fill")
    ]

    static func sound(for group: Int) -> BackgroundSound {
        all.first(where: { $0.group == group }) ?? all[0]
    }
}

enum TimerPreset: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .sixty: return "1 hr"
        case .ninety: return "1.5 hr"
        case .oneTwenty: return "2 hr"
        default: return "\(rawValue) min"
        }
    }
}

struct CustomSound: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var duration: TimeInterval
    var symbol: String
    var folderID: UUID?
    var normalizationGainDecibels: Double
    var measuredRMSDecibels: Double?
    var measuredPeakDecibels: Double?
    var playbackStartOffset: TimeInterval

    var url: URL { URL(fileURLWithPath: path) }

    init(fileURL: URL) throws {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        id = UUID()
        name = fileURL.deletingPathExtension().lastPathComponent
        path = fileURL.path
        duration = Double(file.length) / sampleRate
        symbol = "waveform"
        folderID = nil
        normalizationGainDecibels = 0
        measuredRMSDecibels = nil
        measuredPeakDecibels = nil
        playbackStartOffset = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, duration, symbol, folderID
        case normalizationGainDecibels, measuredRMSDecibels, measuredPeakDecibels
        case playbackStartOffset
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "waveform"
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        normalizationGainDecibels = try values.decodeIfPresent(Double.self, forKey: .normalizationGainDecibels) ?? 0
        measuredRMSDecibels = try values.decodeIfPresent(Double.self, forKey: .measuredRMSDecibels)
        measuredPeakDecibels = try values.decodeIfPresent(Double.self, forKey: .measuredPeakDecibels)
        playbackStartOffset = try values.decodeIfPresent(TimeInterval.self, forKey: .playbackStartOffset) ?? -1
    }
}

struct CustomSoundFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum SoundReference: Codable, Hashable, Identifiable {
    case system(Int)
    case custom(UUID)

    var id: String {
        switch self {
        case .system(let group): return "system-\(group)"
        case .custom(let id): return "custom-\(id.uuidString)"
        }
    }
}

struct PrimaryShortcutActivation: Equatable {
    let shouldChangeSelection: Bool
    let shouldPlayAfterActivation: Bool

    init(isSelected: Bool, isPlaying: Bool) {
        shouldChangeSelection = !isSelected
        shouldPlayAfterActivation = isSelected ? !isPlaying : true
    }
}

enum AudioMixing {
    static func effectiveLayerVolume(master: Double, relativeLayer: Double) -> Double {
        min(max(master, 0), 1) * min(max(relativeLayer, 0), 1)
    }
}

struct LoopTiming: Equatable {
    let duration: TimeInterval
    let crossfadeDuration: TimeInterval
    let transitionStart: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration
        crossfadeDuration = min(30, duration / 2)
        transitionStart = duration - crossfadeDuration
    }

    init(sourceDuration: TimeInterval, maximumDuration: TimeInterval) {
        self.init(duration: min(sourceDuration, maximumDuration))
    }
}
