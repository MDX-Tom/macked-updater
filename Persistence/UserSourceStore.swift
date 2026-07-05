import Foundation

actor UserSourceStore {
    static let shared = UserSourceStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let sourcesURL: URL

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        sourcesURL = AppDatabase.applicationSupportDirectory().appendingPathComponent("user-sources.json")
    }

    func loadSources() -> [String: UserUpdateSource] {
        guard let data = try? Data(contentsOf: sourcesURL) else {
            return [:]
        }

        do {
            return try decoder.decode([String: UserUpdateSource].self, from: data)
        } catch {
            return [:]
        }
    }

    func save(_ source: UserUpdateSource) {
        var sources = loadSources()
        if source.hasAnySource {
            sources[source.appID] = source
        } else {
            sources.removeValue(forKey: source.appID)
        }
        saveAll(sources)
    }

    func remove(appID: String) {
        var sources = loadSources()
        sources.removeValue(forKey: appID)
        saveAll(sources)
    }

    private func saveAll(_ sources: [String: UserUpdateSource]) {
        do {
            try AppDatabase.ensureApplicationSupportDirectory()
            let data = try encoder.encode(sources)
            try data.write(to: sourcesURL, options: .atomic)
        } catch {
            print("Failed to save user sources: \(error)")
        }
    }
}
