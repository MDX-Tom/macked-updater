import Foundation

actor AppDatabase {
    static let shared = AppDatabase()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let cacheURL: URL

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        cacheURL = Self.applicationSupportDirectory().appendingPathComponent("update-cache.json")
    }

    func loadUpdateCache() -> [String: AppUpdateInfo] {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return [:]
        }

        do {
            return try decoder.decode([String: AppUpdateInfo].self, from: data)
        } catch {
            return [:]
        }
    }

    func saveUpdateCache(_ cache: [String: AppUpdateInfo]) {
        do {
            try Self.ensureApplicationSupportDirectory()
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("Failed to save update cache: \(error)")
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("MackedUpdater", isDirectory: true)
    }

    static func ensureApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory(),
            withIntermediateDirectories: true
        )
    }
}
