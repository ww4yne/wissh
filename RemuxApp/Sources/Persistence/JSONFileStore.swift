import Foundation

enum JSONFileStoreError: LocalizedError, Sendable {
    case invalidDirectory(URL)
    case readFailed(URL, String)
    case decodeFailed(URL, String)
    case encodeFailed(URL, String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let url):
            return "Remux could not create \(url.path)."
        case .readFailed(let url, let message):
            return "Remux could not read \(url.lastPathComponent): \(message)"
        case .decodeFailed(let url, let message):
            return "Remux could not decode \(url.lastPathComponent): \(message)"
        case .encodeFailed(let url, let message):
            return "Remux could not encode \(url.lastPathComponent): \(message)"
        case .writeFailed(let url, let message):
            return "Remux could not write \(url.lastPathComponent): \(message)"
        }
    }
}

actor JSONFileStore<Record: Codable & Sendable> {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(defaultValue: [Record] = []) throws -> [Record] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return defaultValue
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw JSONFileStoreError.readFailed(fileURL, error.localizedDescription)
        }

        do {
            return try decoder.decode([Record].self, from: data)
        } catch {
            throw JSONFileStoreError.decodeFailed(fileURL, error.localizedDescription)
        }
    }

    func save(_ records: [Record]) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw JSONFileStoreError.invalidDirectory(directory)
        }

        let data: Data
        do {
            data = try encoder.encode(records)
        } catch {
            throw JSONFileStoreError.encodeFailed(fileURL, error.localizedDescription)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw JSONFileStoreError.writeFailed(fileURL, error.localizedDescription)
        }
    }
}
