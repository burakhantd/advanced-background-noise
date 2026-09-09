import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class BackgroundSoundsStore: ObservableObject {
    nonisolated static let defaultShortcutGroups = [15, 4, 5, 6, 8]
    nonisolated static let customSymbols = [
        "waveform", "water.waves", "cloud.rain.fill", "drop.fill", "flame.fill",
        "leaf.fill", "wind", "moon.stars.fill", "bird.fill", "tree.fill",
        "mountain.2.fill", "music.note", "sparkles", "heart.fill", "headphones"
    ]

    @Published var isEnabled = false
    @Published var volume = 0.35
    @Published var selectedGroup = 1
    @Published var selectedCustomID: UUID?
    @Published var timerEnd: Date?
    @Published private var timerTick = Date()
    @Published private(set) var activeTimerMinutes: Int?
    @Published var errorMessage: String?
    @Published private(set) var shortcuts: [SoundReference]
    @Published private(set) var customSounds: [CustomSound]
    @Published private(set) var customFolders: [CustomSoundFolder]
    @Published private(set) var layerShortcuts: [UUID?]
    @Published private(set) var activeLayerSoundID: UUID?
    @Published private(set) var isLayerEnabled = false
   @Published private(set) var layerVolume: Double
   @Published private(set) var isVinylNoiseEnabled = false
    @Published private(set) var menuOpenCount = 0

   private let bridge: SystemBackgroundSounds
    private let customPlayer = CustomLoopPlayer()
    private let layerPlayer = CustomLoopPlayer()
    private let vinylNoisePlayer = VinylNoisePlayer()
    private let mediaPlaybackStopper = MediaPlaybackStopper()
    private let shortcutsDefaultsKey = "soundShortcuts"
    private let legacyShortcutDefaultsKey = "favoriteSoundGroups"
    private let customSoundsDefaultsKey = "customSounds"
    private let customFoldersDefaultsKey = "customSoundFolders"
    private let layerShortcutsDefaultsKey = "layerSoundShortcuts"
    private let layerVolumeDefaultsKey = "layerVolume"
    private let relativeLayerVolumeDefaultsKey = "layerVolumeIsRelativeV2"
    private static let activeTimerMinutesDefaultsKey = "activeTimerMinutes"
    private static let activeTimerEndDefaultsKey = "activeTimerEnd"
    private var pollTimer: Timer?
    private var timerCompletionTimer: Timer?
    private var isApplyingChange = false
    private var isAdjustingVolume = false

    init(bridge: SystemBackgroundSounds = SystemBackgroundSounds()) {
        let defaults = UserDefaults.standard

        if
            let data = defaults.data(forKey: customSoundsDefaultsKey),
            let decoded = try? JSONDecoder().decode([CustomSound].self, from: data)
        {
            customSounds = decoded.compactMap { storedSound in
                var sound = storedSound
                let sourceURL = sound.url
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    if let localURL = try? CustomSoundLibrary.copyIntoLibrary(sourceURL: sourceURL, id: sound.id) {
                        sound.path = localURL.path
                    }
                    return sound
                }
                if let recoveredURL = CustomSoundLibrary.recoveryURL(for: sourceURL, id: sound.id) {
                    if let localURL = try? CustomSoundLibrary.copyIntoLibrary(sourceURL: recoveredURL, id: sound.id) {
                        sound.path = localURL.path
                    } else {
                        sound.path = recoveredURL.path
                    }
                    return sound
                }
                return nil
            }
        } else {
            customSounds = []
        }

        if
            let data = defaults.data(forKey: customFoldersDefaultsKey),
            let decoded = try? JSONDecoder().decode([CustomSoundFolder].self, from: data)
        {
            customFolders = decoded
        } else {
            customFolders = []
        }

        let decodedShortcuts: [SoundReference]?
        if let data = defaults.data(forKey: shortcutsDefaultsKey) {
            decodedShortcuts = try? JSONDecoder().decode([SoundReference].self, from: data)
        } else {
            decodedShortcuts = nil
        }

        if let decodedShortcuts, decodedShortcuts.count == 5 {
            shortcuts = decodedShortcuts
        } else if let legacy = defaults.array(forKey: legacyShortcutDefaultsKey) {
            let groups = legacy.compactMap { ($0 as? NSNumber)?.intValue }
            shortcuts = groups.count == 5 ? groups.map(SoundReference.system) : Self.defaultShortcuts
        } else {
            shortcuts = Self.defaultShortcuts
        }

        self.bridge = bridge
        activeLayerSoundID = nil
        let savedLayerVolume = defaults.object(forKey: layerVolumeDefaultsKey) as? NSNumber
        layerVolume = savedLayerVolume.map { min(max($0.doubleValue, 0), 1) } ?? 0.28
        layerShortcuts = []

        if
            let data = defaults.data(forKey: layerShortcutsDefaultsKey),
            let decoded = try? JSONDecoder().decode([UUID?].self, from: data),
            decoded.count == 5
        {
            layerShortcuts = decoded
        } else {
            layerShortcuts = Array(customSounds.prefix(5).map(\.id).map(Optional.some))
            layerShortcuts += Array(repeating: nil, count: 5 - layerShortcuts.count)
        }
        let validFolderIDs = Set(customFolders.map(\.id))
        for index in customSounds.indices {
            if let folderID = customSounds[index].folderID, !validFolderIDs.contains(folderID) {
                customSounds[index].folderID = nil
            }
        }

        let validCustomIDs = Set(customSounds.map(\.id))
        shortcuts = shortcuts.enumerated().map { index, reference in
            if case .custom(let id) = reference, !validCustomIDs.contains(id) {
                return Self.defaultShortcuts[index]
            }
            return reference
        }
        layerShortcuts = layerShortcuts.map { id in
            guard let id, validCustomIDs.contains(id) else { return nil }
            return id
        }

        persistShortcuts()
        persistLayerShortcuts()
        persistCustomSounds()
        refresh()
        if !defaults.bool(forKey: relativeLayerVolumeDefaultsKey) {
            let previousAbsoluteVolume = layerVolume
            if volume > 0.001 {
                layerVolume = min(previousAbsoluteVolume / volume, 1)
            }
            defaults.set(layerVolume, forKey: layerVolumeDefaultsKey)
            defaults.set(true, forKey: relativeLayerVolumeDefaultsKey)
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        normalizeSoundsNeedingAnalysis()
    }

    deinit {
        pollTimer?.invalidate()
        timerCompletionTimer?.invalidate()
    }

    nonisolated static var defaultShortcuts: [SoundReference] {
        defaultShortcutGroups.map(SoundReference.system)
    }

    var selectedSystemSound: BackgroundSound { .sound(for: selectedGroup) }
    var selectedCustomSound: CustomSound? { customSounds.first { $0.id == selectedCustomID } }
    var selectedTitle: String { selectedCustomSound?.name ?? selectedSystemSound.title }
    var selectedSymbol: String { selectedCustomSound?.symbol ?? selectedSystemSound.symbol }
    var isCustomSelected: Bool { selectedCustomSound != nil }
    var isAvailable: Bool { isCustomSelected || bridge.isAvailable }
    var hasAnyPlayback: Bool { isEnabled || isLayerEnabled || isVinylNoiseEnabled }
    var menuBarSymbol: String {
        if isEnabled { return selectedSymbol }
        if let activeLayerSound { return activeLayerSound.symbol }
        return "waveform.circle"
    }
    var activeLayerSound: CustomSound? {
        customSounds.first { $0.id == activeLayerSoundID }
    }
    var effectiveLayerVolume: Double {
        AudioMixing.effectiveLayerVolume(master: volume, relativeLayer: layerVolume)
    }
    var remainingTime: TimeInterval { max(timerEnd?.timeIntervalSince(timerTick) ?? 0, 0) }

    var remainingLabel: String {
        let total = Int(remainingTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func title(for reference: SoundReference) -> String {
       switch reference {
       case .system(let group): return BackgroundSound.sound(for: group).title
       case .custom(let id): return customSounds.first(where: { $0.id == id })?.name ?? "Custom Sound"
       }
   }

    func notifyMenuOpened() {
        menuOpenCount += 1
    }

   func symbol(for reference: SoundReference) -> String {
       switch reference {
       case .system(let group): return BackgroundSound.sound(for: group).symbol
        case .custom(let id): return customSounds.first(where: { $0.id == id })?.symbol ?? "waveform"
        }
    }

    func isSelected(_ reference: SoundReference) -> Bool {
        switch reference {
        case .system(let group): return !isCustomSelected && selectedGroup == group
        case .custom(let id): return selectedCustomID == id
        }
    }

    func folderName(for sound: CustomSound) -> String {
        guard let folderID = sound.folderID else { return "Unfiled" }
        return customFolders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
    }

    func customSounds(in folderID: UUID?) -> [CustomSound] {
        customSounds.filter { $0.folderID == folderID }
    }

    func layerSound(at index: Int) -> CustomSound? {
        guard layerShortcuts.indices.contains(index), let id = layerShortcuts[index] else { return nil }
        return customSounds.first { $0.id == id }
    }

    func isLayerActive(at index: Int) -> Bool {
        guard let sound = layerSound(at: index) else { return false }
        return isLayerEnabled && activeLayerSoundID == sound.id
    }

    func toggleLayer(at index: Int) {
        guard let sound = layerSound(at: index) else {
            addCustomSound()
            return
        }

        if isLayerEnabled, activeLayerSoundID == sound.id {
            layerPlayer.stop()
            isLayerEnabled = false
            activeLayerSoundID = nil
            return
        }

        do {
            layerPlayer.stop()
            try layerPlayer.play(
                url: sound.url,
                volume: effectiveLayerVolume,
                maximumLoopDuration: 10 * 60,
                normalizationGainDecibels: sound.normalizationGainDecibels,
                playbackStartOffset: sound.playbackStartOffset
            )
            activeLayerSoundID = sound.id
            isLayerEnabled = true
            errorMessage = nil
        } catch {
            isLayerEnabled = false
            activeLayerSoundID = nil
            errorMessage = error.localizedDescription
        }
    }

    func replaceLayerShortcut(at index: Int, with soundID: UUID) {
        guard layerShortcuts.indices.contains(index), customSounds.contains(where: { $0.id == soundID }) else { return }
        if let existingIndex = layerShortcuts.firstIndex(where: { $0 == soundID }), existingIndex != index {
            layerShortcuts.swapAt(index, existingIndex)
        } else {
            layerShortcuts[index] = soundID
        }
        persistLayerShortcuts()
    }

    func clearLayerShortcut(at index: Int) {
        guard layerShortcuts.indices.contains(index) else { return }
        if let id = layerShortcuts[index], activeLayerSoundID == id {
            layerPlayer.stop()
            activeLayerSoundID = nil
            isLayerEnabled = false
        }
        layerShortcuts[index] = nil
        persistLayerShortcuts()
    }

    func layerVolumeChanged(_ newValue: Double) {
        layerVolume = min(max(newValue, 0), 1)
        layerPlayer.setVolume(effectiveLayerVolume)
        UserDefaults.standard.set(layerVolume, forKey: layerVolumeDefaultsKey)
        UserDefaults.standard.set(true, forKey: relativeLayerVolumeDefaultsKey)
    }

    func toggleVinylNoise() {
        if isVinylNoiseEnabled {
            vinylNoisePlayer.stop()
            isVinylNoiseEnabled = false
            return
        }

        do {
            try vinylNoisePlayer.start()
            isVinylNoiseEnabled = true
            errorMessage = nil
        } catch {
            isVinylNoiseEnabled = false
            errorMessage = "Could not start vinyl texture: \(error.localizedDescription)"
        }
    }

    func setVinylMusicVolume(_ volume: Double) {
        vinylNoisePlayer.setMusicVolume(volume)
    }

    func toggle() {
        if let custom = selectedCustomSound {
            apply {
                if isEnabled {
                    customPlayer.stop()
                    isEnabled = false
                    timerEnd = nil
                } else {
                    try bridge.setEnabled(false)
                    try customPlayer.play(
                        url: custom.url,
                        volume: volume,
                        normalizationGainDecibels: custom.normalizationGainDecibels,
                        playbackStartOffset: custom.playbackStartOffset
                    )
                    isEnabled = true
                }
            }
            return
        }

        apply {
            try bridge.setEnabled(!isEnabled)
            isEnabled.toggle()
            if !isEnabled { timerEnd = nil }
        }
    }

    func activatePrimary(_ reference: SoundReference) {
        let activation = PrimaryShortcutActivation(
            isSelected: isSelected(reference),
            isPlaying: isEnabled
        )
        if activation.shouldChangeSelection { choose(reference) }
        if isEnabled != activation.shouldPlayAfterActivation { toggle() }
    }

    func choose(_ reference: SoundReference) {
        switch reference {
        case .system(let group): choose(BackgroundSound.sound(for: group))
        case .custom(let id):
            guard let sound = customSounds.first(where: { $0.id == id }) else { return }
            choose(sound)
        }
    }

    func choose(_ sound: BackgroundSound) {
        let shouldContinuePlaying = isEnabled
        apply {
            customPlayer.stop()
            try bridge.select(group: sound.group)
            selectedCustomID = nil
            selectedGroup = sound.group
            if shouldContinuePlaying { try bridge.setEnabled(true) }
            isEnabled = shouldContinuePlaying
        }
    }

    func choose(_ sound: CustomSound) {
        let shouldContinuePlaying = isEnabled
        apply {
            try bridge.setEnabled(false)
            customPlayer.stop()
            selectedCustomID = sound.id
            if shouldContinuePlaying {
                try customPlayer.play(
                    url: sound.url,
                    volume: volume,
                    normalizationGainDecibels: sound.normalizationGainDecibels,
                    playbackStartOffset: sound.playbackStartOffset
                )
            }
            isEnabled = shouldContinuePlaying
            timerEnd = nil
        }
    }

    func addCustomSound() {
        let panel = NSOpenPanel()
        panel.title = "Add Custom Background Sound"
        panel.prompt = "Ekle"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let sound = try insertCustomSound(from: url)
            choose(sound)
            normalizeSound(id: sound.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeCustomSound(_ sound: CustomSound) {
        if selectedCustomID == sound.id {
            customPlayer.stop()
            selectedCustomID = nil
            isEnabled = false
            timerEnd = nil
        }
        if activeLayerSoundID == sound.id {
            layerPlayer.stop()
            activeLayerSoundID = nil
            isLayerEnabled = false
        }
        customSounds.removeAll { $0.id == sound.id }
        layerShortcuts = layerShortcuts.map { $0 == sound.id ? nil : $0 }
        shortcuts = shortcuts.enumerated().map { index, reference in
            reference == .custom(sound.id) ? Self.defaultShortcuts[index] : reference
        }
        persistCustomSounds()
        persistShortcuts()
        persistLayerShortcuts()
    }

    func addFolder(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !customFolders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        customFolders.append(CustomSoundFolder(name: name))
        customFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistCustomFolders()
        return true
    }

    func removeFolder(_ folder: CustomSoundFolder) {
        for index in customSounds.indices where customSounds[index].folderID == folder.id {
            customSounds[index].folderID = nil
        }
        customFolders.removeAll { $0.id == folder.id }
        persistCustomSounds()
        persistCustomFolders()
    }

    func setFolder(_ folderID: UUID?, for soundID: UUID) {
        guard let index = customSounds.firstIndex(where: { $0.id == soundID }) else { return }
        customSounds[index].folderID = folderID
        persistCustomSounds()
    }

    func setSymbol(_ symbol: String, for soundID: UUID) {
        guard Self.customSymbols.contains(symbol) else { return }
        guard let index = customSounds.firstIndex(where: { $0.id == soundID }) else { return }
        customSounds[index].symbol = symbol
        persistCustomSounds()
    }

    func replaceShortcut(at index: Int, with reference: SoundReference) {
        guard shortcuts.indices.contains(index) else { return }
        if let existingIndex = shortcuts.firstIndex(of: reference), existingIndex != index {
            shortcuts.swapAt(index, existingIndex)
        } else {
            shortcuts[index] = reference
        }
        persistShortcuts()
    }

    func volumeChanged(_ newValue: Double) {
        let masterVolume = min(max(newValue, 0), 1)
        volume = masterVolume
        layerPlayer.setVolume(effectiveLayerVolume)
        do {
            if isCustomSelected {
                customPlayer.setVolume(masterVolume)
            } else {
                try bridge.setVolume(masterVolume)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func volumeEditingChanged(_ isEditing: Bool) {
        isAdjustingVolume = isEditing
        if !isEditing { refresh() }
    }

    func startTimer(minutes: Int) {
        let end = Date().addingTimeInterval(Double(max(minutes, 1) * 60))
        if let custom = selectedCustomSound {
            apply {
                if !isEnabled {
                    try bridge.setEnabled(false)
                    try customPlayer.play(
                        url: custom.url,
                        volume: volume,
                        normalizationGainDecibels: custom.normalizationGainDecibels,
                        playbackStartOffset: custom.playbackStartOffset
                    )
                }
                isEnabled = true
                timerEnd = end
                scheduleTimerCompletion(at: end, minutes: minutes)
            }
            return
        }

        apply {
            try bridge.startTimer(minutes: minutes)
            isEnabled = true
            timerEnd = end
            scheduleTimerCompletion(at: end, minutes: minutes)
        }
    }

    func cancelTimer() {
        timerCompletionTimer?.invalidate()
        timerCompletionTimer = nil
        activeTimerMinutes = nil
        UserDefaults.standard.removeObject(forKey: Self.activeTimerMinutesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.activeTimerEndDefaultsKey)
        if isCustomSelected {
            timerEnd = nil
            return
        }
        apply {
            try bridge.cancelTimer()
            timerEnd = nil
        }
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ].compactMap(URL.init(string:))
        for url in urls where NSWorkspace.shared.open(url) { break }
    }

    func quit() {
        customPlayer.stop()
        layerPlayer.stop()
        vinylNoisePlayer.stop()
        NSApplication.shared.terminate(nil)
    }

    func refresh() {
        guard !isApplyingChange else { return }
        if isCustomSelected {
            if timerEnd != nil { timerTick = Date() }
            if let timerEnd, timerEnd <= Date(), isEnabled {
                customPlayer.stop()
                isEnabled = false
                self.timerEnd = nil
            }
            return
        }

        do {
            let state = try bridge.snapshot()
            let refreshedTimerEnd = state.timerEnabled ? state.timerEnd : nil
            if isEnabled != state.isEnabled { isEnabled = state.isEnabled }
            if !isAdjustingVolume, abs(volume - state.volume) > 0.001 {
                volume = state.volume
                layerPlayer.setVolume(effectiveLayerVolume)
            }
            if selectedGroup != state.selectedGroup { selectedGroup = state.selectedGroup }
            if timerEnd != refreshedTimerEnd { timerEnd = refreshedTimerEnd }
            if let refreshedTimerEnd {
                timerTick = Date()
                if activeTimerMinutes == nil {
                    restoreOrInferActiveTimer(for: refreshedTimerEnd)
                }
            } else if activeTimerMinutes != nil {
                activeTimerMinutes = nil
                UserDefaults.standard.removeObject(forKey: Self.activeTimerMinutesDefaultsKey)
                UserDefaults.standard.removeObject(forKey: Self.activeTimerEndDefaultsKey)
            }
            if errorMessage != nil { errorMessage = nil }
        } catch {
            let message = error.localizedDescription
            if errorMessage != message { errorMessage = message }
        }
    }

    private func restoreOrInferActiveTimer(for end: Date) {
        let defaults = UserDefaults.standard
        if let savedMinutes = defaults.object(forKey: Self.activeTimerMinutesDefaultsKey) as? Int,
           let savedEnd = defaults.object(forKey: Self.activeTimerEndDefaultsKey) as? TimeInterval,
           abs(end.timeIntervalSince1970 - savedEnd) < 5 {
            activeTimerMinutes = savedMinutes
            scheduleTimerCompletion(at: end, minutes: savedMinutes)
            return
        }

        let remainingMinutes = end.timeIntervalSinceNow / 60
        if let matched = TimerPreset.allCases.filter({ Double($0.rawValue) >= remainingMinutes - 0.5 }).min(by: { $0.rawValue < $1.rawValue }) ?? TimerPreset.allCases.last {
            activeTimerMinutes = matched.rawValue
            scheduleTimerCompletion(at: end, minutes: matched.rawValue)
        }
    }

    private func scheduleTimerCompletion(at end: Date, minutes: Int) {
        timerCompletionTimer?.invalidate()
        activeTimerMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.activeTimerMinutesDefaultsKey)
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.activeTimerEndDefaultsKey)
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishTimerAndStopAllPlayback() }
        }
        timerCompletionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishTimerAndStopAllPlayback() {
        timerCompletionTimer?.invalidate()
        timerCompletionTimer = nil
        customPlayer.stop()
        layerPlayer.stop()
        vinylNoisePlayer.stop()
        try? bridge.cancelTimer()
        try? bridge.setEnabled(false)
        isEnabled = false
        isLayerEnabled = false
        isVinylNoiseEnabled = false
        activeLayerSoundID = nil
        timerEnd = nil
        activeTimerMinutes = nil
        UserDefaults.standard.removeObject(forKey: Self.activeTimerMinutesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.activeTimerEndDefaultsKey)
        mediaPlaybackStopper.stopAll()
    }

    private func persistShortcuts() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: shortcutsDefaultsKey)
    }

    private func persistCustomSounds() {
        guard let data = try? JSONEncoder().encode(customSounds) else { return }
        UserDefaults.standard.set(data, forKey: customSoundsDefaultsKey)
    }

    private func persistCustomFolders() {
        guard let data = try? JSONEncoder().encode(customFolders) else { return }
        UserDefaults.standard.set(data, forKey: customFoldersDefaultsKey)
    }

    private func persistLayerShortcuts() {
        guard let data = try? JSONEncoder().encode(layerShortcuts) else { return }
        UserDefaults.standard.set(data, forKey: layerShortcutsDefaultsKey)
    }

    @discardableResult
    func importCustomSoundSynchronously(from url: URL) throws -> CustomSound {
        let sound = try insertCustomSound(from: url)
        let result = try CustomAudioNormalizer.analyze(url: sound.url)
        applyNormalization(result, to: sound.id)
        return customSounds.first(where: { $0.id == sound.id }) ?? sound
    }

    @discardableResult
    func replaceCustomSoundFileSynchronously(originalURL: URL, replacementURL: URL) throws -> CustomSound {
        let originalPath = originalURL.standardizedFileURL.path
        guard let index = customSounds.firstIndex(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == originalPath
        }) else {
            return try importCustomSoundSynchronously(from: replacementURL)
        }

        let id = customSounds[index].id
        var replacement = try CustomSound(fileURL: replacementURL)
        replacement.path = try CustomSoundLibrary.copyIntoLibrary(sourceURL: replacementURL, id: id).path
        customSounds[index].path = replacement.path
        customSounds[index].duration = replacement.duration
        customSounds[index].normalizationGainDecibels = 0
        customSounds[index].measuredRMSDecibels = nil
        customSounds[index].measuredPeakDecibels = nil
        customSounds[index].playbackStartOffset = 0
        persistCustomSounds()

        let result = try CustomAudioNormalizer.analyze(url: replacement.url)
        applyNormalization(result, to: id)
        return customSounds[index]
    }

    private func insertCustomSound(from url: URL) throws -> CustomSound {
        let standardizedPath = url.standardizedFileURL.path
        if let existing = customSounds.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == standardizedPath }) {
            return existing
        }

        var sound = try CustomSound(fileURL: url)
        sound.path = try CustomSoundLibrary.copyIntoLibrary(sourceURL: url, id: sound.id).path
        customSounds.append(sound)
        if let emptyIndex = layerShortcuts.firstIndex(where: { $0 == nil }) {
            layerShortcuts[emptyIndex] = sound.id
            persistLayerShortcuts()
        }
        persistCustomSounds()
        return sound
    }

    private func normalizeSoundsNeedingAnalysis() {
        let sounds = customSounds
            .filter { $0.measuredRMSDecibels == nil || $0.playbackStartOffset < 0 }
            .map { ($0.id, $0.url) }
        Task { @MainActor [weak self] in
            for (id, url) in sounds {
                guard !Task.isCancelled else { return }
                let result = await Task.detached(priority: .utility) {
                    try? CustomAudioNormalizer.analyze(url: url)
                }.value
                guard let self, let result else { continue }
                self.applyNormalization(result, to: id)
            }
        }
    }

    private func normalizeSound(id: UUID) {
        guard let sound = customSounds.first(where: { $0.id == id }) else { return }
        let url = sound.url
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                try? CustomAudioNormalizer.analyze(url: url)
            }.value
            guard let self, let result else { return }
            self.applyNormalization(result, to: id)
        }
    }

    private func applyNormalization(_ result: AudioNormalizationResult, to id: UUID) {
        guard let index = customSounds.firstIndex(where: { $0.id == id }) else { return }
        customSounds[index].normalizationGainDecibels = result.gainDecibels
        customSounds[index].measuredRMSDecibels = result.measuredRMSDecibels
        customSounds[index].measuredPeakDecibels = result.measuredPeakDecibels
        customSounds[index].playbackStartOffset = result.leadingSilenceDuration
        persistCustomSounds()

        if selectedCustomID == id {
            customPlayer.setNormalizationGain(decibels: result.gainDecibels)
        }
        if activeLayerSoundID == id {
            layerPlayer.setNormalizationGain(decibels: result.gainDecibels)
        }
    }

    private func apply(_ operation: () throws -> Void) {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            try operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
