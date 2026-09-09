import AppKit
import Combine
import Dispatch
import Foundation
import Darwin

extension Notification.Name {
    static let appleMusicArtworkDidUpdate = Notification.Name("appleMusicArtworkDidUpdate")
}

final class AppleMusicArtworkManager: @unchecked Sendable {
    static let shared = AppleMusicArtworkManager()

    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "AmbientSounds.AppleMusicArtwork", qos: .utility)
    private var inFlightKeys = Set<String>()

    private init() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("AmbientSoundsArtworks", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        self.cacheDirectory = temp
    }

    func cachedArtworkURL(for trackKey: String) -> URL? {
        guard !trackKey.isEmpty else { return nil }
        let safeName = sanitize(trackKey)
        let fileURL = cacheDirectory.appendingPathComponent("\(safeName).png")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    func requestArtwork(for trackKey: String, onNewArtwork: (@Sendable () -> Void)? = nil) {
        requestArtworkData(
            for: trackKey,
            script: """
            if application "Music" is running then
                tell application "Music"
                    try
                        if (count of artworks of current track) > 0 then
                            return raw data of artwork 1 of current track
                        end if
                    end try
                end tell
            end if
            return missing value
            """,
            onNewArtwork: onNewArtwork
        )
    }

    func requestArtwork(
        for trackKey: String,
        title: String,
        artist: String,
        onNewArtwork: (@Sendable () -> Void)? = nil
    ) {
        let escapedTitle = appleScriptString(title)
        let escapedArtist = appleScriptString(artist)
        requestArtworkData(
            for: trackKey,
            script: """
            if application "Music" is running then
                tell application "Music"
                    try
                        set currentItem to current track
                        if name of currentItem is "\(escapedTitle)" and artist of currentItem is "\(escapedArtist)" then
                            if (count of artworks of currentItem) > 0 then
                                return raw data of artwork 1 of currentItem
                            end if
                        end if
                    end try
                end tell
            end if
            return missing value
            """,
            onNewArtwork: onNewArtwork
        )
    }

    private func requestArtworkData(
        for trackKey: String,
        script: String,
        onNewArtwork: (@Sendable () -> Void)? = nil
    ) {
        queue.async {
            guard !trackKey.isEmpty else { return }
            let safeName = self.sanitize(trackKey)
            let fileURL = self.cacheDirectory.appendingPathComponent("\(safeName).png")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return
            }
            guard !self.inFlightKeys.contains(trackKey) else { return }
            self.inFlightKeys.insert(trackKey)

            var error: NSDictionary?
            if let desc = NSAppleScript(source: script)?.executeAndReturnError(&error),
               desc.descriptorType != typeNull {
                let data = desc.data
                if data.count > 0 {
                    try? data.write(to: fileURL)
                    self.inFlightKeys.remove(trackKey)
                    onNewArtwork?()
                    return
                }
            }
            self.inFlightKeys.remove(trackKey)
        }
    }

    private func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func sanitize(_ key: String) -> String {
        let safe = key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let result = String(String.UnicodeScalarView(safe))
        return result.isEmpty ? "track_\(abs(key.hashValue))" : result
    }
}


final class FavoriteTracksManager: @unchecked Sendable {
    static let shared = FavoriteTracksManager()

    private let userDefaultsKey = "persistedFavoritedTrackKeys"
    private let queue = DispatchQueue(label: "AmbientSounds.FavoriteTracks", qos: .utility)
    private var favoritedKeys: Set<String>

    private init() {
        if let array = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            favoritedKeys = Set(array)
        } else {
            favoritedKeys = []
        }
    }

    static func trackKey(source: MediaSource, title: String, artist: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(source.rawValue):\(cleanTitle)---\(cleanArtist)"
    }

    func isFavorited(source: MediaSource, title: String, artist: String) -> Bool {
        guard !title.isEmpty || !artist.isEmpty else { return false }
        let key = Self.trackKey(source: source, title: title, artist: artist)
        return queue.sync {
            favoritedKeys.contains(key)
        }
    }

    func setFavorited(_ favorited: Bool, source: MediaSource, title: String, artist: String) {
        guard !title.isEmpty || !artist.isEmpty else { return }
        let key = Self.trackKey(source: source, title: title, artist: artist)
        queue.sync {
            if favorited {
                favoritedKeys.insert(key)
            } else {
                favoritedKeys.remove(key)
            }
            let list = Array(favoritedKeys)
            UserDefaults.standard.set(list, forKey: userDefaultsKey)
        }
    }
}

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

enum MediaSlotAction: String, CaseIterable, Identifiable, Sendable {
    case `repeat`
    case shuffle
    case favorite
    case queue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repeat: return "Repeat"
        case .shuffle: return "Shuffle"
        case .favorite: return "Favorite / Liked"
        case .queue: return "Up Next / Queue"
        }
    }
}

struct QueueTrackItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let artist: String
    let duration: String
    let artworkURL: URL?

    init(title: String, artist: String, duration: String, artworkURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

enum RepeatMode: String, Equatable, Sendable {
    case off, all, one

    /// Cycles through all three states: off -> all (loop) -> one (track loop) -> off
    func next() -> RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var symbolName: String {
        self == .one ? "repeat.1" : "repeat"
    }
    var isActive: Bool { self != .off }
}

struct PlaybackIntentState: Equatable, Sendable {
    private(set) var pendingState: Bool?

    init() {
        pendingState = nil
    }

    mutating func nextDesiredState(observedState: Bool) -> Bool {
        let desiredState = !(pendingState ?? observedState)
        pendingState = desiredState
        return desiredState
    }

    @discardableResult
    mutating func reconcile(observedState: Bool) -> Bool {
        guard let pendingState else { return true }
        guard pendingState == observedState else { return false }
        self.pendingState = nil
        return true
    }

    mutating func reset() {
        pendingState = nil
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
    let repeatMode: RepeatMode
    let isShuffleEnabled: Bool
    let isFavorited: Bool

    init(
        title: String = "",
        artist: String = "",
        isPlaying: Bool = false,
        source: MediaSource = .none,
        elapsedTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        artworkURL: URL? = nil,
        volume: Double = 1,
        repeatMode: RepeatMode = .off,
        isShuffleEnabled: Bool = false,
        isFavorited: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.source = source
        self.elapsedTime = elapsedTime
        self.duration = duration
        self.artworkURL = artworkURL
        self.volume = min(max(volume, 0), 1)
        self.repeatMode = repeatMode
        self.isShuffleEnabled = isShuffleEnabled
        self.isFavorited = isFavorited
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
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: clampedPosition(position), duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
        )
    }

    func updatingVolume(_ volume: Double) -> NowPlayingItem {
        NowPlayingItem(
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: elapsedTime, duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
        )
    }

    func updatingPlaybackState(_ isPlaying: Bool) -> NowPlayingItem {
        NowPlayingItem(
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: elapsedTime, duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
        )
    }

    func updatingRepeatMode(_ repeatMode: RepeatMode) -> NowPlayingItem {
        NowPlayingItem(
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: elapsedTime, duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
        )
    }

    func updatingShuffle(_ isShuffleEnabled: Bool) -> NowPlayingItem {
        NowPlayingItem(
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: elapsedTime, duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
        )
    }

    func updatingFavorited(_ isFavorited: Bool) -> NowPlayingItem {
        NowPlayingItem(
            title: title, artist: artist, isPlaying: isPlaying, source: source,
            elapsedTime: elapsedTime, duration: duration,
            artworkURL: artworkURL, volume: volume,
            repeatMode: repeatMode, isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
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
    enum Control: Equatable {
        case play
        case previous
        case togglePlayback
        case pause
        case next
    }

    private let commandQueue = DispatchQueue(label: "AmbientSounds.MediaCommands", qos: .userInitiated)

    static func control(forDesiredPlaybackState isPlaying: Bool) -> Control {
        isPlaying ? .play : .pause
    }

    func getNowPlaying(
        preferredSource: MediaSource? = nil,
        completion: @escaping (NowPlayingItem?) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            var spotify = Self.spotifyItem()
            if let sp = spotify {
                if let liveState = SpotifyAccessibility.favorite() {
                    spotify = sp.updatingFavorited(liveState)
                    FavoriteTracksManager.shared.setFavorited(liveState, source: .spotify, title: sp.title, artist: sp.artist)
                } else if FavoriteTracksManager.shared.isFavorited(source: .spotify, title: sp.title, artist: sp.artist) {
                    spotify = sp.updatingFavorited(true)
                }
            }
            var music = Self.musicItem()
            if let mus = music {
                if mus.isFavorited {
                    FavoriteTracksManager.shared.setFavorited(true, source: .music, title: mus.title, artist: mus.artist)
                } else if FavoriteTracksManager.shared.isFavorited(source: .music, title: mus.title, artist: mus.artist) {
                    music = mus.updatingFavorited(true)
                }
            }
            completion(Self.selectNowPlaying(spotify: spotify, music: music, preferredSource: preferredSource))
        }
    }

    static func selectNowPlaying(
        spotify: NowPlayingItem?,
        music: NowPlayingItem?,
        preferredSource: MediaSource?
    ) -> NowPlayingItem? {
        if (preferredSource == .spotify || preferredSource == .music),
           let preferredSource {
            let preferred = preferredSource == .spotify ? spotify : music
            let other = preferredSource == .spotify ? music : spotify

            // Keep a paused/stopped app selected so the next button press is
            // still sent to the app the user was controlling. Switch only
            // when the other app is genuinely playing.
            if let preferred {
                if preferred.isPlaying { return preferred }
                if let other, other.isPlaying { return other }
                return preferred
            }
        }

        return [spotify, music].compactMap { $0 }.first(where: \.isPlaying) ?? spotify ?? music
    }

    func send(_ control: Control, to source: MediaSource) {
        commandQueue.async {
            let command: String
            switch control {
            case .play: command = "play"
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

    func setRepeat(_ mode: RepeatMode, in source: MediaSource) {
        commandQueue.async {
            let script: String
            switch source {
            case .spotify:
                let repeating = mode != .off
                script = "tell application \"Spotify\" to set repeating to \(repeating)"
            case .music:
                let repeatVal: String
                switch mode {
                case .off: repeatVal = "off"
                case .one: repeatVal = "one"
                case .all: repeatVal = "all"
                }
                script = "tell application \"Music\" to set song repeat to \(repeatVal)"
            case .system, .none:
                return
            }
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    func setShuffle(_ enabled: Bool, in source: MediaSource) {
        commandQueue.async {
            let script: String
            switch source {
            case .spotify:
                script = "tell application \"Spotify\" to set shuffling to \(enabled)"
            case .music:
                script = "tell application \"Music\" to set shuffle enabled to \(enabled)"
            case .system, .none:
                return
            }
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    func toggleFavorite(in source: MediaSource, completion: @escaping (Bool) -> Void) {
        setFavorite(true, in: source, completion: completion)
    }

    func setFavorite(_ favorited: Bool, in source: MediaSource, completion: @escaping (Bool) -> Void) {
        commandQueue.async {
            switch source {
            case .music:
                let boolStr = favorited ? "true" : "false"
                let script = """
                if application "Music" is running then
                    tell application "Music"
                        try
                            set currentTrack to current track
                            set favorited of currentTrack to \(boolStr)
                        end try
                    end tell
                end if
                """
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                completion(error == nil)
                return

            case .spotify:
                DispatchQueue.main.async {
                    StatusBarDelegate.beginSuppressingDismiss()
                }
                let script = """
                tell application "System Events"
                    set prevApp to name of first application process whose frontmost is true
                end tell
                tell application "Spotify" to activate
                delay 0.06
                tell application "System Events"
                    keystroke "b" using {option down, shift down}
                end tell
                delay 0.06
                if prevApp is not "" and prevApp is not "Spotify" then
                    tell application prevApp to activate
                end if
                """
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    StatusBarDelegate.endSuppressingDismiss()
                }
                completion(error == nil)
                return

            case .system, .none:
                completion(false)
            }
        }
    }

    func checkMusicFavoriteState() -> Bool? {
        let script = """
        if application "Music" is running then
            tell application "Music"
                try
                    if favorited of current track is true then
                        return "true"
                    else
                        return "false"
                    end if
                end try
            end tell
        end if
        return ""
        """
        var error: NSDictionary?
        if let desc = NSAppleScript(source: script)?.executeAndReturnError(&error) {
            let str = (desc.stringValue ?? "").lowercased()
            if str == "true" { return true }
            if str == "false" { return false }
        }
        return nil
    }

    func showQueue(in source: MediaSource) {
        // Handled directly inside UI via isShowingQueue
    }

    func fetchUpcomingTracks(for source: MediaSource, completion: @escaping ([QueueTrackItem]) -> Void) {
        commandQueue.async {
            switch source {
            case .music:
                let script = """
                if application "Music" is running then
                    tell application "Music"
                        set currentState to player state as text
                        if currentState is "playing" or currentState is "paused" then
                            try
                                set curTrack to current track
                                set curTrackID to id of curTrack
                                set curPlaylist to current playlist
                                set tNames to name of tracks of curPlaylist
                                set tArtists to artist of tracks of curPlaylist
                                set tIDs to id of tracks of curPlaylist
                                set tTimes to time of tracks of curPlaylist

                                set curIndex to 0
                                set total to count of tIDs
                                repeat with i from 1 to total
                                    if item i of tIDs is curTrackID then
                                        set curIndex to i
                                        exit repeat
                                    end if
                                end repeat

                                set outList to {}
                                if curIndex > 0 and curIndex < total then
                                    set startIdx to curIndex + 1
                                    set endIdx to curIndex + 20
                                    if endIdx > total then set endIdx to total
                                    repeat with i from startIdx to endIdx
                                        set trackID to ""
                                        try
                                            set trackID to persistent ID of track i of curPlaylist
                                        end try
                                        if trackID is "" then set trackID to item i of tIDs
                                        set end of outList to (item i of tNames & "|||" & item i of tArtists & "|||" & item i of tTimes & "|||" & trackID)
                                    end repeat
                                end if
                                return outList
                            end try
                        end if
                    end tell
                end if
                return {}
                """
                var error: NSDictionary?
                guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error),
                      error == nil else {
                    completion([])
                    return
                }
                var items: [QueueTrackItem] = []
                for i in 0..<descriptor.numberOfItems {
                    if let str = descriptor.atIndex(i + 1)?.stringValue {
                        let parts = str.components(separatedBy: "|||")
                        if parts.count >= 2 {
                            let title = parts[0]
                            let artist = parts[1]
                            let duration = parts.count > 2 ? parts[2] : ""
                            let trackKey = parts.count > 3 && !parts[3].isEmpty
                                ? parts[3]
                                : "\(title)---\(artist)"
                            let cachedArtwork = AppleMusicArtworkManager.shared.cachedArtworkURL(for: trackKey)
                            if cachedArtwork == nil {
                                AppleMusicArtworkManager.shared.requestArtwork(
                                    for: trackKey,
                                    title: title,
                                    artist: artist
                                ) {
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(name: .appleMusicArtworkDidUpdate, object: nil)
                                    }
                                }
                            }
                            items.append(QueueTrackItem(
                                title: title,
                                artist: artist,
                                duration: duration,
                                artworkURL: cachedArtwork
                            ))
                        }
                    }
                }
                completion(items)

            case .spotify:
                var items = SpotifyAccessibility.upcomingTracks()
                if !items.isEmpty {
                    completion(items)
                    return
                }

                DispatchQueue.main.async {
                    StatusBarDelegate.beginSuppressingDismiss()
                }

                let script = """
                tell application "System Events"
                    set prevApp to name of first application process whose frontmost is true
                end tell
                tell application "Spotify" to activate
                delay 0.18
                tell application "System Events"
                    key code 12 using {option down, shift down}
                end tell
                delay 0.18
                if prevApp is not "" and prevApp is not "Spotify" then
                    tell application prevApp to activate
                end if
                """
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)

                items = SpotifyAccessibility.upcomingTracks()
                if items.isEmpty {
                    for _ in 0..<8 {
                        Thread.sleep(forTimeInterval: 0.1)
                        items = SpotifyAccessibility.upcomingTracks()
                        if !items.isEmpty { break }
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    StatusBarDelegate.endSuppressingDismiss()
                }
                completion(items)
                return
            case .system, .none:
                completion([])
            }
        }
    }

    func openSpotifyQueue() {
        commandQueue.async {
            let script = "tell application \"Spotify\" to open location \"spotify:collection:queue\""
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
                    set isFav to "false"
                    try
                        if starred of currentItem is true then
                            set isFav to "true"
                        end if
                    end try
                    return {name of currentItem, artist of currentItem, currentState, player position, (duration of currentItem) / 1000, artwork url of currentItem, sound volume, repeating as text, shuffling as text, isFav}
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
                    set repeatVal to song repeat as text
                    set shuffleVal to shuffle enabled as text
                    set isFav to "false"
                    try
                        if favorited of currentItem is true then
                            set isFav to "true"
                        end if
                    on error
                        try
                            if loved of currentItem is true then
                                set isFav to "true"
                            end if
                        end try
                    end try
                    set pID to ""
                    try
                        set pID to persistent ID of currentItem
                    end try
                    if pID is "" then
                        try
                            set pID to (name of currentItem & "---" & artist of currentItem)
                        end try
                    end if
                    return {name of currentItem, artist of currentItem, currentState, player position, duration of currentItem, pID, sound volume, repeatVal, shuffleVal, isFav}
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
        let volume = (descriptor.atIndex(7)?.doubleValue ?? 100) / 100

        let artworkURL: URL?
        if source == .music {
            let trackKey = descriptor.atIndex(6)?.stringValue ?? ""
            if let cached = AppleMusicArtworkManager.shared.cachedArtworkURL(for: trackKey) {
                artworkURL = cached
            } else {
                artworkURL = nil
                // Resolve artwork by the captured track identity. Reading
                // Music's `current track` inside the async request can return
                // a different song after a fast next/playback interaction.
                AppleMusicArtworkManager.shared.requestArtwork(
                    for: trackKey,
                    title: title,
                    artist: artist
                ) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .appleMusicArtworkDidUpdate, object: nil)
                    }
                }
            }
        } else {
            let artworkString = descriptor.atIndex(6)?.stringValue ?? ""
            artworkURL = URL(string: artworkString)
        }

        // Repeat — Music returns "off"/"one"/"all"; Spotify returns "true"/"false"
        let repeatString = (descriptor.atIndex(8)?.stringValue ?? "").lowercased()
        let repeatMode: RepeatMode
        if repeatString.contains("one") { repeatMode = .one }
        else if repeatString.contains("all") || repeatString == "true" { repeatMode = .all }
        else { repeatMode = .off }

        // Shuffle — both apps return "true"/"false"
        let shuffleString = (descriptor.atIndex(9)?.stringValue ?? "").lowercased()
        let isShuffleEnabled = shuffleString == "true"

        // Favorited / Liked
        let favString = (descriptor.numberOfItems >= 10 ? descriptor.atIndex(10)?.stringValue : "")?.lowercased() ?? ""
        let isFavorited = favString == "true"

        guard !title.isEmpty || !artist.isEmpty else { return nil }
        return NowPlayingItem(
            title: title,
            artist: artist,
            isPlaying: state == "playing",
            source: source,
            elapsedTime: elapsed,
            duration: duration,
            artworkURL: artworkURL,
            volume: volume,
            repeatMode: repeatMode,
            isShuffleEnabled: isShuffleEnabled,
            isFavorited: isFavorited
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
    private var refreshTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var playbackIntent = PlaybackIntentState()
    private var isAdjustingVolume = false
    private var volumeUpdateTask: Task<Void, Never>?
    @Published var upcomingTracks: [QueueTrackItem] = []
    @Published var isLoadingQueue = false
    @Published var mediaActionError: String?
    @Published var isFavoritePending = false
    @Published private(set) var favoriteConfirmationToken = 0
    private var favoritePendingTarget: Bool?
    private var favoriteTask: Task<Void, Never>?
    private var artworkObserver: AnyCancellable?
    private var queueRequestID = UUID()

    init(bridge: MediaRemoteBridge = MediaRemoteBridge()) {
        self.bridge = bridge
        self.artworkObserver = NotificationCenter.default.publisher(for: .appleMusicArtworkDidUpdate)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refresh()
                    if !self.upcomingTracks.isEmpty || self.isLoadingQueue {
                        self.loadQueue()
                    }
                }
            }
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
        refreshTask?.cancel()
        refreshTask = nil
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
        let desiredPlaying = playbackIntent.nextDesiredState(observedState: item.isPlaying)
        let control = MediaApplicationBridge.control(forDesiredPlaybackState: desiredPlaying)
        if item.source == .spotify || item.source == .music {
            applicationBridge.send(control, to: item.source)
        } else {
            bridge.send(desiredPlaying ? .play : .pause)
        }
        item = item.updatingPlaybackState(desiredPlaying)
        refreshSoon()
    }

    func toggleRepeat() {
        let nextMode = item.repeatMode.next()
        item = item.updatingRepeatMode(nextMode)
        if item.source == .spotify || item.source == .music {
            applicationBridge.setRepeat(nextMode, in: item.source)
        }
        refreshSoon()
    }

    func toggleShuffle() {
        let nextShuffle = !item.isShuffleEnabled
        item = item.updatingShuffle(nextShuffle)
        if item.source == .spotify || item.source == .music {
            applicationBridge.setShuffle(nextShuffle, in: item.source)
        }
        refreshSoon()
    }

    func toggleFavorite() {
        let target = !item.isFavorited
        let source = item.source
        let title = item.title
        let artist = item.artist

        mediaActionError = nil
        item = item.updatingFavorited(target)
        favoritePendingTarget = target

        FavoriteTracksManager.shared.setFavorited(target, source: source, title: title, artist: artist)

        favoriteTask?.cancel()

        if target {
            // FAVORITING: Apple Music takes a few seconds to sync with cloud, show pending pulse
            isFavoritePending = true
            favoriteTask = Task { [weak self] in
                guard let self else { return }
                let source = self.item.source
                let commandSucceeded = await withCheckedContinuation { continuation in
                    self.applicationBridge.setFavorite(true, in: source) { succeeded in
                        if !succeeded && source == .spotify {
                            Task { @MainActor in
                                self.mediaActionError = "Could not verify the like. Check Accessibility access and the Spotify window."
                            }
                        }
                        continuation.resume(returning: succeeded)
                    }
                }

                var favoriteConfirmed = commandSucceeded
                if source == .music {
                    favoriteConfirmed = false
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(200))
                        if Task.isCancelled { return }
                        if self.applicationBridge.checkMusicFavoriteState() == true {
                            favoriteConfirmed = true
                            break
                        }
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(250))
                }

                if !Task.isCancelled {
                    self.isFavoritePending = false
                    self.favoritePendingTarget = nil
                    if favoriteConfirmed {
                        self.favoriteConfirmationToken &+= 1
                    }
                    self.refresh()
                }
            }
        } else {
            // UNFAVORITING: Apple Music un-favorites instantly. No waiting or pulsing needed.
            isFavoritePending = false
            favoriteTask = Task { [weak self] in
                guard let self else { return }
                let source = self.item.source
                await withCheckedContinuation { continuation in
                    self.applicationBridge.setFavorite(false, in: source) { succeeded in
                        if !succeeded && source == .spotify {
                            Task { @MainActor in
                            self.mediaActionError = "Could not verify the like. Check Accessibility access and the Spotify window."
                            }
                        }
                        continuation.resume()
                    }
                }
                // Hold target protection briefly (1.2s) against background timer polls
                try? await Task.sleep(for: .milliseconds(1200))
                if !Task.isCancelled {
                    self.favoritePendingTarget = nil
                    self.refresh()
                }
            }
        }
    }

    func showQueue() {
        loadQueue()
    }

    func openSpotifyQueue() {
        applicationBridge.openSpotifyQueue()
    }

    func loadQueue() {
        let requestID = UUID()
        queueRequestID = requestID
        let source = item.source
        let title = item.title
        upcomingTracks = []
        isLoadingQueue = true
        applicationBridge.fetchUpcomingTracks(for: item.source) { [weak self] tracks in
            Task { @MainActor in
                guard let self, self.queueRequestID == requestID else { return }
                self.isLoadingQueue = false
                guard self.item.source == source else { return }
                self.upcomingTracks = tracks
            }
        }
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
        let preferredSource = item.source
        applicationBridge.getNowPlaying(preferredSource: preferredSource) { [weak self] applicationItem in
            Task { @MainActor in
                guard let self else { return }
                if let applicationItem {
                    let trackChanged = applicationItem.source != self.item.source
                        || applicationItem.title != self.item.title
                        || applicationItem.artist != self.item.artist
                    if trackChanged {
                        self.playbackIntent.reset()
                        self.favoriteTask?.cancel()
                        self.isFavoritePending = false
                        self.favoritePendingTarget = nil
                    }

                    var refreshed = self.isAdjustingVolume
                        ? applicationItem.updatingVolume(self.item.volume)
                        : applicationItem
                    // Preserve .one state for Spotify since Spotify's AppleScript only returns boolean repeating
                    if applicationItem.source == .spotify && applicationItem.repeatMode == .all && self.item.repeatMode == .one {
                        refreshed = refreshed.updatingRepeatMode(.one)
                    }

                    if self.isFavoritePending, let pending = self.favoritePendingTarget {
                        refreshed = refreshed.updatingFavorited(pending)
                    }

                    if !trackChanged, let pendingPlaybackState = self.playbackIntent.pendingState {
                        if !self.playbackIntent.reconcile(observedState: applicationItem.isPlaying) {
                            // A poll can observe an older state while rapid commands
                            // are still queued. Keep the optimistic state until the
                            // requested state is confirmed.
                            refreshed = refreshed.updatingPlaybackState(pendingPlaybackState)
                        }
                    }

                    if refreshed != self.item { self.item = refreshed }
                    self.refreshInFlight = false
                    if self.playbackIntent.pendingState != nil {
                        self.refreshSoon()
                    }
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
                var refreshed = NowPlayingItem.parse(dictionary)
                if let pendingPlaybackState = self.playbackIntent.pendingState,
                   !self.playbackIntent.reconcile(observedState: refreshed.isPlaying) {
                    refreshed = refreshed.updatingPlaybackState(pendingPlaybackState)
                }
                if refreshed != self.item { self.item = refreshed }
                self.refreshInFlight = false
                if self.playbackIntent.pendingState != nil {
                    self.refreshSoon()
                }
            }
        }
    }

    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.refreshTask = nil
            self?.refresh()
        }
    }
}
