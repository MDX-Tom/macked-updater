import Foundation

struct MacAppStoreChecker {
    func check(app: InstalledApp) async -> AppUpdateInfo? {
        guard app.hasMacAppStoreReceipt else {
            return nil
        }

        let appStoreID = await detectAppStoreID(for: app) ?? app.appStoreID
        let lookupResult = await lookup(app: app, appStoreID: appStoreID)

        let pageURL = lookupResult?.trackViewURL ?? appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
        let latestVersion = lookupResult?.version
        let status: UpdateStatus

        if let latestVersion {
            switch VersionComparator.compare(current: app.shortVersion, latest: latestVersion, currentBuild: app.buildVersion) {
            case .currentOlder:
                status = .updateAvailable
            case .equal, .currentNewer:
                status = .upToDate
            case .unknown:
                status = .unknown
            }
        } else {
            status = .unknown
        }

        let source = UpdateSource(
            kind: .macAppStore,
            name: UpdateSourceKind.macAppStore.title,
            identifier: appStoreID,
            pageURL: pageURL,
            feedURL: nil
        )

        return AppUpdateInfo(
            appID: app.id,
            currentVersion: app.shortVersion,
            latestVersion: latestVersion,
            status: status,
            source: source,
            officialPageURL: pageURL,
            downloadURL: nil,
            releaseNotesURL: pageURL,
            lastCheckedAt: Date(),
            errorMessage: status == .unknown ? "Mac App Store receipt was detected, but the latest version could not be determined." : nil
        )
    }

    private func detectAppStoreID(for app: InstalledApp) async -> String? {
        guard FileManager.default.fileExists(atPath: "/usr/bin/mdls") else {
            return nil
        }

        do {
            let output = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/mdls"),
                arguments: ["-raw", "-name", "kMDItemAppStoreAdamID", app.installPath]
            )
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != "(null)", trimmed != "null", !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        } catch {
            return nil
        }
    }

    private func lookup(app: InstalledApp, appStoreID: String?) async -> AppStoreLookupResult? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        if let appStoreID, !appStoreID.isEmpty {
            components?.queryItems = [URLQueryItem(name: "id", value: appStoreID)]
        } else if let bundleIdentifier = app.bundleIdentifier {
            components?.queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        } else {
            return nil
        }

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }

            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = root["results"] as? [[String: Any]],
                let first = results.first
            else {
                return nil
            }

            return AppStoreLookupResult(
                version: first["version"] as? String,
                trackViewURL: (first["trackViewUrl"] as? String).flatMap(URL.init(string:))
            )
        } catch {
            return nil
        }
    }
}

private struct AppStoreLookupResult {
    var version: String?
    var trackViewURL: URL?
}
