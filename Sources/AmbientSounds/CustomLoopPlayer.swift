import AVFoundation
import Foundation

@MainActor
final class CustomLoopPlayer {
    enum PlayerError: LocalizedError {
        case invalidDuration

        var errorDescription: String? { "Could not read the audio duration." }
    }

    private let engine = AVAudioEngine()
    private let nodes = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let loopMixer = AVAudioMixerNode()
    private let normalizationUnit = AVAudioUnitEQ(numberOfBands: 0)
    private var cachedFiles: [URL: AVAudioFile] = [:]
    private var cachedFileOrder: [URL] = []
    private var file: AVAudioFile?
    private var loopFrameCount: AVAudioFrameCount?
    private var loopStartingFrame: AVAudioFramePosition = 0
    private var timing: LoopTiming?
    private var transitionTask: Task<Void, Never>?
    private var rampTask: Task<Void, Never>?
    private var generation = 0
    private var gains: [Float] = [0, 0]
    private var masterVolume: Float = 0.35

    init() {
        engine.attach(loopMixer)
        engine.attach(normalizationUnit)
        for node in nodes {
            engine.attach(node)
            engine.connect(node, to: loopMixer, format: nil)
        }
        engine.connect(loopMixer, to: normalizationUnit, format: nil)
        engine.connect(normalizationUnit, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        try? engine.start()
    }

    func play(
        url: URL,
        volume: Double,
        maximumLoopDuration: TimeInterval? = nil,
        normalizationGainDecibels: Double = 0,
        playbackStartOffset: TimeInterval = 0
    ) throws {
        stop()

        let audioFile = try preparedFile(for: url)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        guard duration > 0.1 else { throw PlayerError.invalidDuration }

        let clampedOffset = min(max(playbackStartOffset, 0), max(duration - 0.1, 0))
        let availableDuration = duration - clampedOffset
        let loopDuration = min(availableDuration, maximumLoopDuration ?? availableDuration)
        loopStartingFrame = AVAudioFramePosition(clampedOffset * audioFile.processingFormat.sampleRate)
        let frames = min(
            AVAudioFramePosition(loopDuration * audioFile.processingFormat.sampleRate),
            audioFile.length - loopStartingFrame
        )
        guard frames > 0, frames <= AVAudioFramePosition(UInt32.max) else {
            throw PlayerError.invalidDuration
        }

        file = audioFile
        loopFrameCount = AVAudioFrameCount(frames)
        timing = LoopTiming(duration: loopDuration)
        masterVolume = Float(min(max(volume, 0), 1))
        normalizationUnit.globalGain = Float(min(max(normalizationGainDecibels, -18), 12))
        generation += 1

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        startNode(at: 0, gain: 1)
        scheduleTransition(from: 0, to: 1, generation: generation)
    }

    func stop() {
        generation += 1
        transitionTask?.cancel()
        transitionTask = nil
        rampTask?.cancel()
        rampTask = nil
        nodes.forEach { $0.stop() }
        gains = [0, 0]
        file = nil
        loopFrameCount = nil
        timing = nil
    }

    func setVolume(_ volume: Double) {
        masterVolume = Float(min(max(volume, 0), 1))
        applyGains()
    }

    func setNormalizationGain(decibels: Double) {
        normalizationUnit.globalGain = Float(min(max(decibels, -18), 12))
    }

    private func startNode(at index: Int, gain: Float) {
        guard let file, let loopFrameCount else { return }
        let node = nodes[index]
        node.stop()
        gains[index] = gain
        applyGains()
        node.scheduleSegment(file, startingFrame: loopStartingFrame, frameCount: loopFrameCount, at: nil)
        node.play()
    }

    private func scheduleTransition(from outgoing: Int, to incoming: Int, generation: Int) {
        guard let timing else { return }
        let delay = UInt64(timing.transitionStart * 1_000_000_000)

        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.beginTransition(from: outgoing, to: incoming, generation: generation)
        }
    }

    private func beginTransition(from outgoing: Int, to incoming: Int, generation: Int) {
        guard let timing else { return }
        startNode(at: incoming, gain: 0)

        // Schedule the following overlap from the moment the incoming copy starts.
        scheduleTransition(from: incoming, to: outgoing, generation: generation)

        let stepInterval: TimeInterval = 0.02
        let steps = max(Int(timing.crossfadeDuration / stepInterval), 1)
        rampTask?.cancel()
        rampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 0...steps {
                guard !Task.isCancelled, self.generation == generation else { return }
                let progress = Double(step) / Double(steps)
                // Equal-power curves keep perceived loudness stable through the overlap.
                self.gains[outgoing] = Float(cos(progress * .pi / 2))
                self.gains[incoming] = Float(sin(progress * .pi / 2))
                self.applyGains()
                if step < steps {
                    try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
                }
            }
            self.nodes[outgoing].stop()
            self.gains[outgoing] = 0
            self.gains[incoming] = 1
            self.applyGains()
        }
    }

    private func applyGains() {
        for index in nodes.indices {
            nodes[index].volume = gains[index] * masterVolume
        }
    }

    private func preparedFile(for url: URL) throws -> AVAudioFile {
        let key = url.standardizedFileURL
        if let cached = cachedFiles[key] { return cached }

        let opened = try AVAudioFile(forReading: key)
        cachedFiles[key] = opened
        cachedFileOrder.append(key)

        if cachedFileOrder.count > 8 {
            let evicted = cachedFileOrder.removeFirst()
            cachedFiles.removeValue(forKey: evicted)
        }
        return opened
    }
}
