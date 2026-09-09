import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    private var updaterController: SPUStandardUpdaterController?

    override private init() {
        super.init()
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURLString.isEmpty
        else {
            return
        }

        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        if let controller = updaterController {
            controller.checkForUpdates(nil)
        } else {
            // Fallback if SUFeedURL was not set or Sparkle not initialized
            if let repoURL = URL(string: "https://github.com/burakhantd/ambient-sounds/releases") {
                NSWorkspace.shared.open(repoURL)
            }
        }
    }
}
