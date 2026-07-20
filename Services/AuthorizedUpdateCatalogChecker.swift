import Foundation

struct AuthorizedCatalogSearchResult: Hashable, Identifiable {
    var appID: String?
    var bundleIdentifier: String?
    var name: String
    var latestVersion: String
    var officialPageURL: URL?
    var releaseNotesURL: URL?
    var downloadURL: URL?

    var id: String {
        [bundleIdentifier, appID, name]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: ":")
    }
}

struct AuthorizedUpdateCatalogChecker {
    func search(catalogURL: URL, query: String) async throws -> [AuthorizedCatalogSearchResult] {
        let data = try await loadCatalogData(from: catalogURL)
        let catalog = try JSONDecoder().decode(AuthorizedUpdateCatalog.self, from: data)
        let normalizedQuery = query.normalizedAppName

        return try catalog.apps
            .filter { entry in
                guard !normalizedQuery.isEmpty else {
                    return true
                }
                return entry.searchableValues.contains { value in
                    value.normalizedAppName.contains(normalizedQuery)
                }
            }
            .map { try $0.searchResult() }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func check(app: InstalledApp, catalogURL: URL, preferredPageURL: URL? = nil) async -> AppUpdateInfo {
        do {
            let data = try await loadCatalogData(from: catalogURL)
            let catalog = try JSONDecoder().decode(AuthorizedUpdateCatalog.self, from: data)
            let sourceName = catalog.sourceName?.nilIfBlank ?? UpdateSourceKind.authorizedCatalog.title
            let source = UpdateSource(
                kind: .authorizedCatalog,
                name: sourceName,
                identifier: catalogURL.absoluteString,
                pageURL: preferredPageURL,
                feedURL: catalogURL
            )

            guard let entry = catalog.bestEntry(for: app) else {
                return AppUpdateInfo(
                    appID: app.id,
                    currentVersion: app.shortVersion,
                    latestVersion: nil,
                    status: .unknown,
                    source: source,
                    officialPageURL: preferredPageURL,
                    downloadURL: nil,
                    releaseNotesURL: nil,
                    lastCheckedAt: Date(),
                    errorMessage: "No matching entry was found in the authorized catalog."
                )
            }

            let officialPageURL = try entry.validatedURL(
                rawValue: entry.officialPageURLString,
                label: "Catalog official page URL"
            ) ?? preferredPageURL
            let releaseNotesURL = try entry.validatedURL(
                rawValue: entry.releaseNotesURLString,
                label: "Catalog release notes URL"
            )
            let downloadURL = try entry.validatedURL(
                rawValue: entry.downloadURLString ?? entry.downloadPageURLString,
                label: "Catalog download URL"
            )
            let latestVersion = entry.latestVersion.nilIfBlank
            let latestBuild = entry.buildVersion?.nilIfBlank
            let status = statusFor(
                current: app.shortVersion,
                latest: latestVersion,
                currentBuild: app.buildVersion,
                latestBuild: latestBuild
            )

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: latestVersion,
                latestBuildVersion: latestBuild,
                status: status,
                source: UpdateSource(
                    kind: .authorizedCatalog,
                    name: sourceName,
                    identifier: catalogURL.absoluteString,
                    pageURL: officialPageURL,
                    feedURL: catalogURL
                ),
                officialPageURL: officialPageURL,
                downloadURL: downloadURL,
                releaseNotesURL: releaseNotesURL,
                lastCheckedAt: Date(),
                errorMessage: status == .unknown ? "The authorized catalog entry was read, but the version could not be compared safely." : nil
            )
        } catch {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(
                    kind: .authorizedCatalog,
                    name: UpdateSourceKind.authorizedCatalog.title,
                    identifier: catalogURL.absoluteString,
                    pageURL: preferredPageURL,
                    feedURL: catalogURL
                ),
                officialPageURL: preferredPageURL,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    private func loadCatalogData(from catalogURL: URL) async throws -> Data {
        if catalogURL.isFileURL {
            return try Data(contentsOf: catalogURL)
        }

        var request = URLRequest(url: catalogURL)
        request.setValue("MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func statusFor(current: String?, latest: String?, currentBuild: String?, latestBuild: String?) -> UpdateStatus {
        switch VersionComparator.compare(current: current, latest: latest, currentBuild: currentBuild, latestBuild: latestBuild) {
        case .currentOlder:
            return .updateAvailable
        case .equal, .currentNewer:
            return .upToDate
        case .unknown:
            return .unknown
        }
    }
}

private struct AuthorizedUpdateCatalog: Decodable {
    var schemaVersion: Int?
    var sourceName: String?
    var apps: [AuthorizedCatalogEntry]

    func bestEntry(for app: InstalledApp) -> AuthorizedCatalogEntry? {
        apps
            .compactMap { entry -> (entry: AuthorizedCatalogEntry, score: Int)? in
                let score = entry.matchScore(for: app)
                return score > 0 ? (entry, score) : nil
            }
            .sorted { $0.score > $1.score }
            .first?
            .entry
    }
}

private struct AuthorizedCatalogEntry: Decodable {
    var appID: String?
    var bundleIdentifier: String?
    var name: String?
    var latestVersion: String
    var buildVersion: String?
    var officialPageURLString: String?
    var releaseNotesURLString: String?
    var downloadURLString: String?
    var downloadPageURLString: String?

    enum CodingKeys: String, CodingKey {
        case appID
        case bundleIdentifier
        case name
        case latestVersion
        case buildVersion
        case officialPageURLString = "officialPageURL"
        case releaseNotesURLString = "releaseNotesURL"
        case downloadURLString = "downloadURL"
        case downloadPageURLString = "downloadPageURL"
    }

    func matchScore(for app: InstalledApp) -> Int {
        if let bundleIdentifier,
           let appBundleIdentifier = app.bundleIdentifier,
           bundleIdentifier.caseInsensitiveCompare(appBundleIdentifier) == .orderedSame {
            return 100
        }

        if let appID, appID.lowercased() == app.id.lowercased() {
            return 90
        }

        if let name, name.normalizedAppName == app.name.normalizedAppName {
            return 70
        }

        return 0
    }

    func validatedURL(rawValue: String?, label: String) throws -> URL? {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let messages = SourceValidation.validationMessages(label: label, rawURLString: rawValue)
        if !messages.isEmpty {
            throw AuthorizedCatalogError.validationFailure(messages.joined(separator: " "))
        }

        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AuthorizedCatalogError.invalidURL(label)
        }

        return url
    }

    var searchableValues: [String] {
        [appID, bundleIdentifier, name, latestVersion].compactMap { $0?.nilIfBlank }
    }

    func searchResult() throws -> AuthorizedCatalogSearchResult {
        AuthorizedCatalogSearchResult(
            appID: appID?.nilIfBlank,
            bundleIdentifier: bundleIdentifier?.nilIfBlank,
            name: name?.nilIfBlank ?? bundleIdentifier?.nilIfBlank ?? appID?.nilIfBlank ?? "Unknown App",
            latestVersion: latestVersion,
            officialPageURL: try validatedURL(rawValue: officialPageURLString, label: "Catalog official page URL"),
            releaseNotesURL: try validatedURL(rawValue: releaseNotesURLString, label: "Catalog release notes URL"),
            downloadURL: try validatedURL(rawValue: downloadURLString ?? downloadPageURLString, label: "Catalog download URL")
        )
    }
}

private enum AuthorizedCatalogError: LocalizedError {
    case invalidURL(String)
    case validationFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let label):
            return "\(label) is not a valid URL."
        case .validationFailure(let message):
            return message
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedAppName: String {
        lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
