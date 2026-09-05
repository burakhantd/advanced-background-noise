import Foundation

enum CustomSoundLibrary {
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundSoundsMenu/Custom Sounds", isDirectory: true)
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
        let idBasedURL = managedURL(for: missingURL, id: id)
        if FileManager.default.fileExists(atPath: idBasedURL.path) { return idBasedURL }

        let nameBasedURL = directoryURL.appendingPathComponent(missingURL.lastPathComponent)
        return FileManager.default.fileExists(atPath: nameBasedURL.path) ? nameBasedURL : nil
    }
}
