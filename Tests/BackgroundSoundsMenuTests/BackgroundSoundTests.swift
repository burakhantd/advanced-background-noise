import XCTest
import AVFoundation
@testable import BackgroundSoundsMenu

final class BackgroundSoundTests: XCTestCase {
    func testPanelStaysBelowMenuBarForReportedScreenGeometry() {
        let visible = CGRect(x: 0, y: 0, width: 2056, height: 1290)
        let anchor = CGRect(x: 1361, y: 1295.5, width: 32, height: 29)
        for height in [408.0, 530.0] {
            let size = CGSize(width: 386, height: height)
            let frame = CGRect(origin: MenuPanelPlacement.origin(size: size, anchor: anchor, visibleFrame: visible), size: size)
            XCTAssertLessThanOrEqual(frame.maxY, visible.maxY - 6)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testPanelFitsAtEitherEdgeOfSecondaryScreen() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 875)
        for x in [-1440.0, -32.0] {
            let anchor = CGRect(x: x, y: 675, width: 32, height: 24)
            let size = CGSize(width: 386, height: 530)
            let frame = CGRect(origin: MenuPanelPlacement.origin(size: size, anchor: anchor, visibleFrame: visible), size: size)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testArtworkOpensOnlyItsKnownMediaSource() {
        XCTAssertEqual(MediaSource.spotify.applicationBundleIdentifier, "com.spotify.client")
        XCTAssertEqual(MediaSource.music.applicationBundleIdentifier, "com.apple.Music")
        XCTAssertNil(MediaSource.none.applicationBundleIdentifier)
        XCTAssertNil(MediaSource.system.applicationBundleIdentifier)
    }

    func testVinylTextureAssetsAndMusicRelativeLevels() throws {
        let crackleURL = try VinylTextureAssets.crackleURL()
        let needleDropURL = try VinylTextureAssets.needleDropURL()
        XCTAssertGreaterThan(try AVAudioFile(forReading: crackleURL).length, 0)
        XCTAssertGreaterThan(try AVAudioFile(forReading: needleDropURL).length, 0)

        XCTAssertEqual(VinylTextureLevels.crackle(for: 0), 0)
        XCTAssertEqual(VinylTextureLevels.needleDrop(for: 0), 0)
        XCTAssertEqual(VinylTextureLevels.crackle(for: 0.5), 0.16, accuracy: 0.001)
        XCTAssertEqual(VinylTextureLevels.needleDrop(for: 0.5), 0.24, accuracy: 0.001)
        XCTAssertEqual(VinylTextureLevels.crackle(for: 2), 0.32, accuracy: 0.001)
        XCTAssertEqual(VinylTextureLevels.needleDrop(for: 2), 0.48, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(VinylTextureLevels.fadeDuration, 0.2)
    }

    func testAllKnownSystemGroupsAreUniqueAndContiguous() {
        XCTAssertEqual(BackgroundSound.all.map(\.group), Array(1...16))
        XCTAssertEqual(Set(BackgroundSound.all.map(\.name)).count, 16)
    }

    func testUnknownGroupFallsBackSafely() {
        XCTAssertEqual(BackgroundSound.sound(for: 999).group, 1)
    }

    func testTimerLabels() {
        XCTAssertEqual(TimerPreset.fortyFive.label, "45 min")
        XCTAssertEqual(TimerPreset.sixty.label, "1 hr")
        XCTAssertEqual(TimerPreset.thirty.label, "30 min")
        XCTAssertEqual(TimerPreset.ninety.label, "1.5 hr")
        XCTAssertEqual(TimerPreset.oneTwenty.label, "2 hr")
        XCTAssertEqual(TimerPreset.allCases.map(\.rawValue), [15, 30, 45, 60, 90, 120])
    }

    func testTwoMinuteLoopCrossfadesDuringFinalThirtySeconds() {
        let timing = LoopTiming(duration: 120)
        XCTAssertEqual(timing.crossfadeDuration, 30)
        XCTAssertEqual(timing.transitionStart, 90)
    }

    func testShortLoopCapsCrossfadeAtHalfItsDuration() {
        let timing = LoopTiming(duration: 20)
        XCTAssertEqual(timing.crossfadeDuration, 10)
        XCTAssertEqual(timing.transitionStart, 10)
    }

    func testLongSecondaryLayerUsesOnlyTenMinutesAndCrossfadesAtNineThirty() {
        let timing = LoopTiming(sourceDuration: 2_420.636708, maximumDuration: 10 * 60)
        XCTAssertEqual(timing.duration, 600)
        XCTAssertEqual(timing.crossfadeDuration, 30)
        XCTAssertEqual(timing.transitionStart, 570)
    }

    func testNormalizationMatchesAppleMedianLevelWithoutClipping() {
        XCTAssertEqual(
            CustomAudioNormalizer.gainDecibels(measuredRMS: -19.2, measuredPeak: -4.9),
            -3.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CustomAudioNormalizer.gainDecibels(measuredRMS: -28.7, measuredPeak: -3.9),
            2.9,
            accuracy: 0.001
        )
    }

    func testNormalizerFindsFirstAudibleAudioWindow() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("normalizer-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let sampleRate = 48_000.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount: AVAudioFrameCount = 24_000
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = frame < 9_600 ? 0 : 0.1
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let result = try CustomAudioNormalizer.analyze(url: url)
        XCTAssertEqual(result.leadingSilenceDuration, 0.2, accuracy: 0.03)
    }

    func testPrimaryShortcutActivationPlaysSwitchesAndToggles() {
        let stopCurrent = PrimaryShortcutActivation(isSelected: true, isPlaying: true)
        XCTAssertFalse(stopCurrent.shouldChangeSelection)
        XCTAssertFalse(stopCurrent.shouldPlayAfterActivation)

        let playCurrent = PrimaryShortcutActivation(isSelected: true, isPlaying: false)
        XCTAssertFalse(playCurrent.shouldChangeSelection)
        XCTAssertTrue(playCurrent.shouldPlayAfterActivation)

        for isPlaying in [false, true] {
            let switchSound = PrimaryShortcutActivation(isSelected: false, isPlaying: isPlaying)
            XCTAssertTrue(switchSound.shouldChangeSelection)
            XCTAssertTrue(switchSound.shouldPlayAfterActivation)
        }
    }

    func testLayerVolumeIsRelativeToMasterVolume() {
        XCTAssertEqual(
            AudioMixing.effectiveLayerVolume(master: 0.8, relativeLayer: 0.25),
            0.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AudioMixing.effectiveLayerVolume(master: 0.4, relativeLayer: 1),
            0.4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AudioMixing.effectiveLayerVolume(master: -1, relativeLayer: 2),
            0,
            accuracy: 0.0001
        )
    }

    func testNowPlayingInfoParsesMediaRemoteDictionary() {
        let item = NowPlayingItem.parse([
            "kMRMediaRemoteNowPlayingInfoTitle": "Midnight City",
            "kMRMediaRemoteNowPlayingInfoArtist": "M83",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1)
        ])

        XCTAssertEqual(item.title, "Midnight City")
        XCTAssertEqual(item.artist, "M83")
        XCTAssertTrue(item.isPlaying)
        XCTAssertTrue(item.hasContent)
    }

    func testMediaRemoteBridgeIsAvailableOnCurrentMacOS() {
        XCTAssertTrue(MediaRemoteBridge().isAvailable)
    }

    func testNowPlayingSeekPositionClampsToTrackDuration() {
        let item = NowPlayingItem(
            title: "Memory Lane",
            artist: "Can Bora Tanzer",
            source: .spotify,
            elapsedTime: 88,
            duration: 344,
            volume: 0.42
        )

        XCTAssertEqual(item.updatingElapsedTime(-5).elapsedTime, 0)
        XCTAssertEqual(item.updatingElapsedTime(172).elapsedTime, 172)
        XCTAssertEqual(item.updatingElapsedTime(900).elapsedTime, 344)
        XCTAssertEqual(item.updatingElapsedTime(172).volume, 0.42)
        XCTAssertEqual(item.updatingVolume(0.75).volume, 0.75)
    }

    func testArtworkAccentPrefersAColorfulDominantCluster() throws {
        let grayPixel: [UInt8] = [105, 105, 105, 255]
        let redPixel: [UInt8] = [225, 42, 36, 255]
        let pixels = Array(repeating: grayPixel, count: 10).flatMap { $0 }
            + Array(repeating: redPixel, count: 4).flatMap { $0 }
        let accent = try XCTUnwrap(ArtworkColorExtractor.dominantAccent(rgba: pixels))

        XCTAssertGreaterThan(accent.red, 0.8)
        XCTAssertLessThan(accent.green, 0.25)
        XCTAssertLessThan(accent.blue, 0.25)
    }

    func testDarkArtworkAccentIsLiftedWithoutLosingItsHue() {
        let darkGreen = ArtworkAccent(red: 0.02, green: 0.08, blue: 0.04)
        let lifted = darkGreen.lifted(toMinimumLuminance: 0.42)

        XCTAssertEqual(lifted.perceivedLuminance, 0.42, accuracy: 0.001)
        XCTAssertGreaterThan(lifted.green, lifted.red)
        XCTAssertGreaterThan(lifted.green, lifted.blue)
    }

    func testMediaVolumeHoverStaysOpenAcrossButtonPopoverAndDragTransitions() {
        var hover = MediaVolumeHoverState()

        hover.buttonHoverChanged(true)
        hover.buttonHoverChanged(false)
        XCTAssertTrue(hover.isPresented)

        hover.popoverHoverChanged(true)
        hover.dismissIfIdle()
        XCTAssertTrue(hover.isPresented)

        hover.editingChanged(true)
        hover.popoverHoverChanged(false)
        hover.dismissIfIdle()
        XCTAssertTrue(hover.isPresented)

        hover.editingChanged(false)
        hover.dismissIfIdle()
        XCTAssertFalse(hover.isPresented)
    }


    func testDefaultShortcutsAreFiveUniqueKnownSounds() {
        let shortcuts = BackgroundSoundsStore.defaultShortcutGroups
        XCTAssertEqual(shortcuts.count, 5)
        XCTAssertEqual(Set(shortcuts).count, 5)
        XCTAssertTrue(shortcuts.allSatisfy { (1...16).contains($0) })
    }

    func testSoundReferencesRoundTripWithCustomAndSystemSounds() throws {
        let references: [SoundReference] = [.system(15), .custom(UUID()), .system(4)]
        let data = try JSONEncoder().encode(references)
        XCTAssertEqual(try JSONDecoder().decode([SoundReference].self, from: data), references)
    }

    func testDefaultShortcutReferencesMatchLegacyGroups() {
        XCTAssertEqual(
            BackgroundSoundsStore.defaultShortcuts,
            BackgroundSoundsStore.defaultShortcutGroups.map(SoundReference.system)
        )
    }

    func testNativeBridgeCanReadCurrentSystemState() throws {
        let bridge = SystemBackgroundSounds()
        XCTAssertTrue(bridge.isAvailable)
        let snapshot = try bridge.snapshot()
        XCTAssertTrue((1...16).contains(snapshot.selectedGroup))
        XCTAssertTrue((0...1).contains(snapshot.volume))
    }

    func testNativeFortyFiveMinuteTimerEndsInFortyFiveMinutes() throws {
        guard ProcessInfo.processInfo.environment["RUN_NATIVE_TIMER_TEST"] == "1" else {
            throw XCTSkip("Native timer integration test is opt-in because it briefly changes system audio state.")
        }

        let bridge = SystemBackgroundSounds()
        let initialState = try bridge.snapshot()
        guard initialState.timerEnd == nil else {
            throw XCTSkip("An existing user timer is active.")
        }

        defer {
            try? bridge.cancelTimer()
            try? bridge.setEnabled(initialState.isEnabled)
        }

        let expectedEnd = Date().addingTimeInterval(45 * 60)
        try bridge.startTimer(minutes: 45)
        let actualEnd = try XCTUnwrap(bridge.snapshot().timerEnd)
        XCTAssertEqual(actualEnd.timeIntervalSince1970, expectedEnd.timeIntervalSince1970, accuracy: 2)
    }
}
