import Foundation

enum LegacyContainerMigration {
    private static let containerRelativePath = "Library/Containers/dev.tommy.parsec/Data/Library/Application Support/Parsec"

    static func migrateIfNeeded() {
        let fileManager = FileManager.default
        let destinationURL = StorageConstants.applicationSupportURL
        let stateURL = destinationURL.appending(path: StorageConstants.stateFileName)
        let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let legacyURL = URL(fileURLWithPath: realHome).appending(path: containerRelativePath)
        guard !fileManager.fileExists(atPath: stateURL.path), fileManager.fileExists(atPath: legacyURL.path) else { return }
        let legacyItems = (try? fileManager.contentsOfDirectory(at: legacyURL, includingPropertiesForKeys: nil)) ?? []
        for itemURL in legacyItems {
            try? fileManager.copyItem(at: itemURL, to: destinationURL.appending(path: itemURL.lastPathComponent))
        }
    }
}
