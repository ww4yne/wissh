import Foundation

enum ApplicationStorage {
    static func remuxRoot(
        overridePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root: URL
        if let overridePath {
            root = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            root = try fileManager
                .url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                .appendingPathComponent("Remux", isDirectory: true)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
