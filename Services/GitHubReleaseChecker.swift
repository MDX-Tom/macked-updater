import Foundation

struct GitHubReleaseChecker {
    func check(app: InstalledApp, releasesURL: URL, preferredPageURL: URL? = nil) async -> AppUpdateInfo {
        guard let repository = GitHubRepository(releasesURL: releasesURL) else {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(kind: .githubReleases, name: UpdateSourceKind.githubReleases.title, identifier: releasesURL.absoluteString, pageURL: releasesURL, feedURL: nil),
                officialPageURL: preferredPageURL ?? releasesURL,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: "The GitHub Releases URL could not be parsed."
            )
        }

        do {
            let apiURL = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases/latest")!
            var request = URLRequest(url: apiURL)
            request.setValue("MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }

            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = root["tag_name"] as? String
            else {
                throw URLError(.cannotParseResponse)
            }

            let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let htmlURL = (root["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesURL
            let bodyURL = preferredPageURL ?? URL(string: "https://github.com/\(repository.owner)/\(repository.name)")
            let status: UpdateStatus

            switch VersionComparator.compare(current: app.shortVersion, latest: latestVersion, currentBuild: app.buildVersion) {
            case .currentOlder:
                status = .updateAvailable
            case .equal, .currentNewer:
                status = .upToDate
            case .unknown:
                status = .unknown
            }

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: latestVersion,
                status: status,
                source: UpdateSource(kind: .githubReleases, name: UpdateSourceKind.githubReleases.title, identifier: releasesURL.absoluteString, pageURL: htmlURL, feedURL: nil),
                officialPageURL: bodyURL,
                downloadURL: nil,
                releaseNotesURL: htmlURL,
                lastCheckedAt: Date(),
                errorMessage: status == .unknown ? "GitHub returned a release tag that could not be compared safely." : nil
            )
        } catch {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(kind: .githubReleases, name: UpdateSourceKind.githubReleases.title, identifier: releasesURL.absoluteString, pageURL: releasesURL, feedURL: nil),
                officialPageURL: preferredPageURL ?? releasesURL,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }
}

private struct GitHubRepository {
    var owner: String
    var name: String

    init?(releasesURL: URL) {
        guard releasesURL.host?.lowercased().contains("github.com") == true else {
            return nil
        }

        let parts = releasesURL.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            return nil
        }

        owner = parts[0]
        name = parts[1]
    }
}
