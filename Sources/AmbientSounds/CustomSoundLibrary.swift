import Foundation

enum CustomSoundLibrary {
    private static let legacyCustomSoundsDirectoryURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundSoundsMenu/Custom Sounds", isDirectory: true)
    }()

    private static let legacyUserSoundsDirectoryURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundSoundsMenu/UserSounds", isDirectory: true)
    }()

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ambient Sounds/UserSounds", isDirectory: true)
    }

    static func managedURL(for sourceURL: URL, id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).\(sourceURL.pathExtension)")
    }

    static func copyIntoLibrary(sourceURL: URL, id: UUID) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let source = sourceURL.standardizedFileURL
        if source.path.hasPrefix(directoryURL.standardizedFileURL.path + "/") { return source }

        let destination = managedURL(for: source, id: id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    static func recoveryURL(for missingURL: URL, id: UUID) -> URL? {
        let fileManager = FileManager.default
        let directories = [directoryURL, legacyUserSoundsDirectoryURL, legacyCustomSoundsDirectoryURL]

        for directory in directories {
            let idBasedURL = directory.appendingPathComponent("\(id.uuidString).\(missingURL.pathExtension)")
            if fileManager.fileExists(atPath: idBasedURL.path) { return idBasedURL }
        }

        for directory in directories {
            let nameBasedURL = directory.appendingPathComponent(missingURL.lastPathComponent)
            if fileManager.fileExists(atPath: nameBasedURL.path) { return nameBasedURL }
        }
        return nil
    }
}
