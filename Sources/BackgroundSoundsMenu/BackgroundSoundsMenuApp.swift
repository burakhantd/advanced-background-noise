import SwiftUI

@main
struct BackgroundSoundsMenuApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        _ = BackgroundSoundsMenuApp()
        let delegate = StatusBarDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor
    init() {
        if CommandLine.arguments.contains("--probe-now-playing-and-exit") {
            let bridge = MediaRemoteBridge()
            let applicationBridge = MediaApplicationBridge()
            var callbackReceived = false
            var parsedItem = NowPlayingItem()
            var keyCount = 0
            applicationBridge.getNowPlaying { applicationItem in
                callbackReceived = true
                if let applicationItem {
                    parsedItem = applicationItem
                } else {
                    bridge.getNowPlayingInfo { dictionary in
                        keyCount = dictionary.count
                        parsedItem = NowPlayingItem.parse(dictionary)
                    }
                }
            }

            let deadline = Date().addingTimeInterval(2)
            while !callbackReceived, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            print(
                "callback=\(callbackReceived) keys=\(keyCount) "
                    + "title=\(!parsedItem.title.isEmpty) artist=\(!parsedItem.artist.isEmpty) "
                    + "playing=\(parsedItem.isPlaying) source=\(parsedItem.source.rawValue)"
            )
            Foundation.exit(callbackReceived && parsedItem.hasContent ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        if
            let argumentIndex = CommandLine.arguments.firstIndex(of: "--benchmark-playback-and-exit"),
            CommandLine.arguments.indices.contains(argumentIndex + 1)
        {
            let url = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
            do {
                let player = CustomLoopPlayer()
                let coldStartedAt = CFAbsoluteTimeGetCurrent()
                try player.play(url: url, volume: 0, maximumLoopDuration: 600)
                let coldElapsed = CFAbsoluteTimeGetCurrent() - coldStartedAt
                player.stop()

                let warmStartedAt = CFAbsoluteTimeGetCurrent()
                try player.play(url: url, volume: 0, maximumLoopDuration: 600)
                let warmElapsed = CFAbsoluteTimeGetCurrent() - warmStartedAt
                player.stop()
                print(String(format: "cold=%.6f warm=%.6f", coldElapsed, warmElapsed))
                let passed = coldElapsed < 0.030 && warmElapsed < 0.015
                Foundation.exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                Foundation.exit(EXIT_FAILURE)
            }
        }

        let store = BackgroundSoundsStore()
        if
            let argumentIndex = CommandLine.arguments.firstIndex(of: "--replace-sound-and-exit"),
            CommandLine.arguments.indices.contains(argumentIndex + 2)
        {
            let originalURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
            let replacementURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 2])
            do {
                try store.replaceCustomSoundFileSynchronously(
                    originalURL: originalURL,
                    replacementURL: replacementURL
                )
                Foundation.exit(EXIT_SUCCESS)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                Foundation.exit(EXIT_FAILURE)
            }
        }

        if
            let argumentIndex = CommandLine.arguments.firstIndex(of: "--import-sound-and-exit"),
            CommandLine.arguments.indices.contains(argumentIndex + 1)
        {
            let url = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
            do {
                try store.importCustomSoundSynchronously(from: url)
                Foundation.exit(EXIT_SUCCESS)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                Foundation.exit(EXIT_FAILURE)
            }
        }
        StatusBarDelegate.store = store
    }

}
