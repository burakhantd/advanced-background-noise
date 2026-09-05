import AppKit
import Combine
import Dispatch
import Foundation
import Darwin

enum MediaSource: String, Equatable, Sendable {
    case spotify
    case music
    case system
    case none

    var applicationBundleIdentifier: String? {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .system, .none: return nil
        }
    }

    var openApplicationLabel: String {
        switch self {
        case .spotify: return "Open Spotify"
        case .music: return "Open Apple Music"
        case .system, .none: return "Music artwork"
        }
    }
}

struct NowPlayingItem: Equatable, Sendable {
    let title: String
    let artist: String
    let isPlaying: Bool
    let source: MediaSource
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let artworkURL: URL?
    let volume: Double

    init(
        title: String = "",
        artist: String = "",
        isPlaying: Bool = false,
        source: MediaSource = .none,
        elapsedTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        artworkURL: URL? = nil,
        volume: Double = 1
    ) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.source = source
        self.elapsedTime = elapsedTime
        self.duration = duration
        self.artworkURL = artworkURL
        self.volume = min(max(volume, 0), 1)
    }

    var hasContent: Bool { !title.isEmpty || !artist.isEmpty }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }

    func clampedPosition(_ position: TimeInterval) -> TimeInterval {
        guard position.isFinite, duration > 0 else { return 0 }
        return min(max(position, 0), duration)
    }

    func updatingElapsedTime(_ position: TimeInterval) -> NowPlayingItem {
        NowPlayingItem(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            source: source,
            elapsedTime: clampedPosition(position),
            duration: duration,
            artworkURL: artworkURL,
            volume: volume
        )
    }

    func updatingVolume(_ volume: Double) -> NowPlayingItem {
        NowPlayingItem(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            source: source,
            elapsedTime: elapsedTime,
            duration: duration,
            artworkURL: artworkURL,
            volume: volume
        )
    }

    static func parse(_ dictionary: [String: Any]) -> NowPlayingItem {
        func string(_ keys: [String]) -> String {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
            }
            return ""
        }

        let title = string(["kMRMediaRemoteNowPlayingInfoTitle", "title"])
        let artist = string(["kMRMediaRemoteNowPlayingInfoArtist", "artist"])
        let rate = (dictionary["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            ?? (dictionary["playbackRate"] as? NSNumber)?.doubleValue
            ?? 0
        let elapsed = (dictionary["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let duration = (dictionary["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        return NowPlayingItem(
            title: title,
            artist: artist,
            isPlaying: rate > 0,
            source: .system,
            elapsedTime: elapsed,
            duration: duration
        )
    }
}

final class MediaApplicationBridge {
    enum Control {
        case previous
        case togglePlayback
        case pause
        case next
    }

    private let commandQueue = DispatchQueue(label: "BackgroundSoundsMenu.MediaCommands", qos: .userInitiated)

    func getNowPlaying(completion: @escaping (NowPlayingItem?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let spotify = Self.spotifyItem()
            let music = Self.musicItem()
            completion([spotify, music].compactMap { $0 }.first(where: \.isPlaying) ?? spotify ?? music)
        }
    }

    func send(_ control: Control, to source: MediaSource) {
        commandQueue.async {
            let command: String
            switch control {
            case .previous: command = "previous track"
            case .togglePlayback: command = "playpause"
            case .pause: command = "pause"
            case .next: command = "next track"
            }

            let applicationName = source == .music ? "Music" : "Spotify"
            let source = "tell application \"\(applicationName)\" to \(command)"
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }

    func pauseAll() {
        send(.pause, to: .spotify)
        send(.pause, to: .music)
    }

    func seek(to position: TimeInterval, in source: MediaSource) {
        commandQueue.async {
            let applicationName = source == .music ? "Music" : "Spotify"
            let seconds = String(
                format: "%.3f",
                locale: Locale(identifier: "en_US_POSIX"),
                max(position, 0)
            )
            let script = "tell application \"\(applicationName)\" to set player position to \(seconds)"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    func setVolume(_ volume: Double, in source: MediaSource) {
        commandQueue.async {
            let applicationName = source == .music ? "Music" : "Spotify"
            let percent = Int((min(max(volume, 0), 1) * 100).rounded())
            let script = "tell application \"\(applicationName)\" to set sound volume to \(percent)"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    private static func spotifyItem() -> NowPlayingItem? {
        parseApplicationResult(
            source: .spotify,
            script: """
            if application "Spotify" is running then
                tell application "Spotify"
                    set currentState to player state as text
                    set currentItem to current track
                    return {name of currentItem, artist of currentItem, currentState, player position, (duration of currentItem) / 1000, artwork url of currentItem, sound volume}
                end tell
            end if
            return {}
            """
        )
    }

    private static func musicItem() -> NowPlayingItem? {
        parseApplicationResult(
            source: .music,
            script: """
            if application "Music" is running then
                tell application "Music"
                    set currentState to player state as text
                    set currentItem to current track
                    return {name of currentItem, artist of currentItem, currentState, player position, duration of currentItem, "", sound volume}
                end tell
            end if
            return {}
            """
        )
    }

    private static func parseApplicationResult(source: MediaSource, script: String) -> NowPlayingItem? {
        var error: NSDictionary?
        guard
            let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error),
            error == nil,
            descriptor.numberOfItems >= 5
        else { return nil }

        let title = descriptor.atIndex(1)?.stringValue ?? ""
        let artist = descriptor.atIndex(2)?.stringValue ?? ""
        let state = descriptor.atIndex(3)?.stringValue ?? ""
        let elapsed = descriptor.atIndex(4)?.doubleValue ?? 0
        let duration = descriptor.atIndex(5)?.doubleValue ?? 0
        let artworkString = descriptor.atIndex(6)?.stringValue ?? ""
        let volume = (descriptor.atIndex(7)?.doubleValue ?? 100) / 100
        guard !title.isEmpty || !artist.isEmpty else { return nil }
        return NowPlayingItem(
            title: title,
            artist: artist,
            isPlaying: state == "playing",
            source: source,
            elapsedTime: elapsed,
            duration: duration,
            artworkURL: URL(string: artworkString),
            volume: volume
        )
    }
}

final class MediaPlaybackStopper {
    private let applicationBridge = MediaApplicationBridge()
    private let mediaRemoteBridge = MediaRemoteBridge()

    func stopAll() {
        applicationBridge.pauseAll()
        mediaRemoteBridge.send(.pause)
    }
}

final class MediaRemoteBridge {
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, InfoCallback) -> Void
    private typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool
    private typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void

    private let handle: UnsafeMutableRawPointer?

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW | RTLD_LOCAL
        )
        if let rawFunction = symbol(named: "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let function = unsafeBitCast(rawFunction, to: RegisterForNotifications.self)
            function(.main)
        }
    }

    var isAvailable: Bool {
        handle != nil
            && symbol(named: "MRMediaRemoteGetNowPlayingInfo") != nil
            && symbol(named: "MRMediaRemoteSendCommand") != nil
    }

    func getNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        guard let rawFunction = symbol(named: "MRMediaRemoteGetNowPlayingInfo") else {
            completion([:])
            return
        }
        let function = unsafeBitCast(rawFunction, to: GetNowPlayingInfo.self)
        let callback: InfoCallback = { dictionary in
            completion(dictionary as? [String: Any] ?? [:])
        }
        function(.main, callback)
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        guard let rawFunction = symbol(named: "MRMediaRemoteSendCommand") else { return false }
        let function = unsafeBitCast(rawFunction, to: SendCommand.self)
        return function(command.rawValue, nil)
    }

    private func symbol(named name: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }
}

@MainActor
final class MediaControllerStore: ObservableObject {
    @Published private(set) var item = NowPlayingItem()

    private let bridge: MediaRemoteBridge
    private let applicationBridge = MediaApplicationBridge()
    private var timer: Timer?
    private var refreshInFlight = false
    private var isAdjustingVolume = false
    private var volumeUpdateTask: Task<Void, Never>?

    init(bridge: MediaRemoteBridge = MediaRemoteBridge()) {
        self.bridge = bridge
    }

    var isAvailable: Bool { bridge.isAvailable }

    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func openSourceApplication() {
        guard let bundleID = item.source.applicationBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func previous() {
        if item.source == .spotify || item.source == .music {
            applicationBridge.send(.previous, to: item.source)
        } else {
            bridge.send(.previousTrack)
        }
        refreshSoon()
    }

    func togglePlayback() {
        if item.source == .spotify || item.source == .music {
            applicationBridge.send(.togglePlayback, to: item.source)
        } else {
            bridge.send(.togglePlayPause)
        }
        item = NowPlayingItem(
            title: item.title,
            artist: item.artist,
            isPlaying: !item.isPlaying,
            source: item.source,
            elapsedTime: item.elapsedTime,
            duration: item.duration,
            artworkURL: item.artworkURL,
            volume: item.volume
        )
        refreshSoon()
    }

    func next() {
        if item.source == .spotify || item.source == .music {
            applicationBridge.send(.next, to: item.source)
        } else {
            bridge.send(.nextTrack)
        }
        refreshSoon()
    }

    func seek(to position: TimeInterval) {
        let clampedPosition = item.clampedPosition(position)
        guard item.duration > 0 else { return }

        if item.source == .spotify || item.source == .music {
            applicationBridge.seek(to: clampedPosition, in: item.source)
        }
        item = item.updatingElapsedTime(clampedPosition)
        refreshSoon()
    }

    func setVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 1)
        let source = item.source
        item = item.updatingVolume(clampedVolume)
        guard source == .spotify || source == .music else { return }

        volumeUpdateTask?.cancel()
        volumeUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled, let self else { return }
            self.applicationBridge.setVolume(clampedVolume, in: source)
        }
    }

    func volumeEditingChanged(_ isEditing: Bool) {
        isAdjustingVolume = isEditing
        if !isEditing { refreshSoon() }
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        applicationBridge.getNowPlaying { [weak self] applicationItem in
            Task { @MainActor in
                guard let self else { return }
                if let applicationItem {
                    let refreshed = self.isAdjustingVolume
                        ? applicationItem.updatingVolume(self.item.volume)
                        : applicationItem
                    if refreshed != self.item { self.item = refreshed }
                    self.refreshInFlight = false
                } else {
                    self.refreshFromMediaRemote()
                }
            }
        }
    }

    private func refreshFromMediaRemote() {
        bridge.getNowPlayingInfo { [weak self] dictionary in
            Task { @MainActor in
                guard let self else { return }
                let refreshed = NowPlayingItem.parse(dictionary)
                if refreshed != self.item { self.item = refreshed }
                self.refreshInFlight = false
            }
        }
    }

    private func refreshSoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.refresh()
        }
    }
}
