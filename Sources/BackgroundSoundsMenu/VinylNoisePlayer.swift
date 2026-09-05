import AVFoundation
import Foundation

struct VinylTextureLevels {
    static let crackleScale = 0.32
    static let needleDropScale = 0.48
    static let fadeDuration: TimeInterval = 0.35

    static func crackle(for musicVolume: Double) -> Float {
        Float(min(max(musicVolume, 0), 1) * crackleScale)
    }

    static func needleDrop(for musicVolume: Double) -> Float {
        Float(min(max(musicVolume, 0), 1) * needleDropScale)
    }
}

enum VinylTextureAssets {
    enum AssetError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "Vinyl audio asset not found: \(name).wav"
            }
        }
    }

    static func crackleURL(in bundle: Bundle = .main) throws -> URL {
        try url(named: "VinylCrackleLoop", in: bundle)
    }

    static func needleDropURL(in bundle: Bundle = .main) throws -> URL {
        try url(named: "VinylNeedleDrop", in: bundle)
    }

    private static func url(named name: String, in bundle: Bundle) throws -> URL {
        if let bundled = bundle.url(forResource: name, withExtension: "wav") {
            return bundled
        }

        #if DEBUG
        // Lets `swift run` and tests use the source assets before app packaging.
        let developmentURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).wav")
        guard FileManager.default.fileExists(atPath: developmentURL.path) else {
            throw AssetError.missing(name)
        }
        return developmentURL
        #else
        throw AssetError.missing(name)
        #endif
    }
}

@MainActor
final class VinylNoisePlayer {
    private var cracklePlayer: AVAudioPlayer?
    private var needleDropPlayer: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var musicVolume = 1.0

    func start() throws {
        fadeTask?.cancel()
        stopPlayersImmediately()

        let crackle = try AVAudioPlayer(contentsOf: VinylTextureAssets.crackleURL())
        crackle.numberOfLoops = -1
        crackle.volume = 0
        crackle.prepareToPlay()

        let needleDrop = try AVAudioPlayer(contentsOf: VinylTextureAssets.needleDropURL())
        needleDrop.numberOfLoops = 0
        needleDrop.volume = VinylTextureLevels.needleDrop(for: musicVolume)
        needleDrop.prepareToPlay()

        cracklePlayer = crackle
        needleDropPlayer = needleDrop
        crackle.play()
        needleDrop.play()
        fadeCrackle(
            from: 0,
            to: VinylTextureLevels.crackle(for: musicVolume),
            stopWhenFinished: false
        )
    }

    func setMusicVolume(_ volume: Double) {
        musicVolume = min(max(volume, 0), 1)
        guard cracklePlayer != nil || needleDropPlayer != nil else { return }
        fadeCrackle(
            from: cracklePlayer?.volume ?? 0,
            to: VinylTextureLevels.crackle(for: musicVolume),
            stopWhenFinished: false
        )
        needleDropPlayer?.setVolume(
            VinylTextureLevels.needleDrop(for: musicVolume),
            fadeDuration: 0.12
        )
    }

    func stop() {
        fadeTask?.cancel()
        needleDropPlayer?.setVolume(0, fadeDuration: 0.16)
        guard let cracklePlayer, cracklePlayer.isPlaying else {
            stopPlayersImmediately()
            return
        }
        fadeCrackle(from: cracklePlayer.volume, to: 0, stopWhenFinished: true)
    }

    private func fadeCrackle(from start: Float, to target: Float, stopWhenFinished: Bool) {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = 14
            let stepDuration = VinylTextureLevels.fadeDuration / Double(steps)
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                self.cracklePlayer?.volume = start + ((target - start) * progress)
                try? await Task.sleep(for: .seconds(stepDuration))
            }
            if stopWhenFinished { self.stopPlayersImmediately() }
            self.fadeTask = nil
        }
    }

    private func stopPlayersImmediately() {
        cracklePlayer?.stop()
        cracklePlayer?.currentTime = 0
        needleDropPlayer?.stop()
        needleDropPlayer?.currentTime = 0
        cracklePlayer = nil
        needleDropPlayer = nil
    }
}
