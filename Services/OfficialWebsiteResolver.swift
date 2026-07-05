import Foundation

struct OfficialWebsiteResolver {
    func unresolvedInfo(for app: InstalledApp) -> AppUpdateInfo {
        let searchURL = makeSearchURL(for: app)
        let source = UpdateSource.manualSearch(url: searchURL)
        return AppUpdateInfo.unknown(for: app, source: source)
    }

    func makeSearchURL(for app: InstalledApp) -> URL {
        let components = [
            app.name,
            app.bundleIdentifier,
            "official app update mac"
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        var urlComponents = URLComponents(string: "https://duckduckgo.com/")!
        urlComponents.queryItems = [URLQueryItem(name: "q", value: components)]
        return urlComponents.url!
    }
}
