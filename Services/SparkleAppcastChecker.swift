import Foundation

struct SparkleAppcastChecker {
    func check(
        app: InstalledApp,
        feedURL: URL,
        sourceKind: UpdateSourceKind = .sparkleAppcast,
        sourceName: String = UpdateSourceKind.sparkleAppcast.title,
        preferredPageURL: URL? = nil
    ) async -> AppUpdateInfo {
        do {
            let data = try await loadAppcastData(from: feedURL)

            let parser = SparkleAppcastParser(data: data)
            let items = try parser.parse()
            guard let latest = latestItem(from: items) else {
                return AppUpdateInfo(
                    appID: app.id,
                    currentVersion: app.shortVersion,
                    latestVersion: nil,
                    status: .unknown,
                    source: UpdateSource(kind: sourceKind, name: sourceName, identifier: feedURL.absoluteString, pageURL: preferredPageURL, feedURL: feedURL),
                    officialPageURL: preferredPageURL,
                    downloadURL: nil,
                    releaseNotesURL: nil,
                    lastCheckedAt: Date(),
                    errorMessage: "No update item was found in the appcast."
                )
            }

            let latestVersion = latest.displayVersion
            let status = statusFor(current: app.shortVersion, latest: latestVersion, currentBuild: app.buildVersion, latestBuild: latest.buildVersion)
            let source = UpdateSource(
                kind: sourceKind,
                name: sourceName,
                identifier: feedURL.absoluteString,
                pageURL: preferredPageURL ?? latest.pageURL,
                feedURL: feedURL
            )

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: latestVersion,
                latestBuildVersion: latest.buildVersion,
                status: status,
                source: source,
                officialPageURL: preferredPageURL ?? latest.pageURL,
                downloadURL: latest.downloadURL,
                releaseNotesURL: latest.releaseNotesURL ?? latest.pageURL,
                lastCheckedAt: Date(),
                errorMessage: status == .unknown ? "The appcast was read, but the version could not be compared safely." : nil
            )
        } catch {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(kind: sourceKind, name: sourceName, identifier: feedURL.absoluteString, pageURL: preferredPageURL, feedURL: feedURL),
                officialPageURL: preferredPageURL,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    private func loadAppcastData(from feedURL: URL) async throws -> Data {
        if feedURL.isFileURL {
            return try Data(contentsOf: feedURL)
        }

        let (data, response) = try await URLSession.shared.data(from: feedURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func latestItem(from items: [SparkleAppcastItem]) -> SparkleAppcastItem? {
        var best: SparkleAppcastItem?

        for item in items where item.displayVersion != nil {
            guard let currentBest = best else {
                best = item
                continue
            }

            let comparison = VersionComparator.compare(
                current: currentBest.displayVersion,
                latest: item.displayVersion,
                currentBuild: currentBest.buildVersion,
                latestBuild: item.buildVersion
            )

            if comparison == .currentOlder {
                best = item
            }
        }

        return best ?? items.first
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

private struct SparkleAppcastItem {
    var title: String?
    var shortVersion: String?
    var buildVersion: String?
    var downloadURL: URL?
    var releaseNotesURL: URL?
    var pageURL: URL?

    var displayVersion: String? {
        shortVersion ?? buildVersion ?? title?.extractLikelyVersion()
    }
}

private final class SparkleAppcastParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parserError: Error?
    private var items: [SparkleAppcastItem] = []
    private var currentItem: SparkleAppcastItem?
    private var currentElement: String = ""
    private var buffer: String = ""

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [SparkleAppcastItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        if parser.parse() {
            return items
        }

        throw parser.parserError ?? parserError ?? URLError(.cannotParseResponse)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let lower = elementName.lowercased()
        currentElement = lower
        buffer = ""

        if lower == "item" {
            currentItem = SparkleAppcastItem()
            return
        }

        guard currentItem != nil else {
            return
        }

        if lower.hasSuffix("enclosure") {
            applyEnclosureAttributes(attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let lower = elementName.lowercased()
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var item = currentItem else {
            return
        }

        switch lower {
        case "item":
            items.append(item)
            currentItem = nil
        case "title":
            item.title = text.nilIfBlank
            currentItem = item
        case "link":
            item.pageURL = URL(string: text)
            currentItem = item
        default:
            if lower.hasSuffix("shortversionstring") {
                item.shortVersion = text.nilIfBlank
                currentItem = item
            } else if lower.hasSuffix("version") {
                item.buildVersion = text.nilIfBlank
                currentItem = item
            } else if lower.hasSuffix("releasenoteslink") {
                item.releaseNotesURL = URL(string: text)
                currentItem = item
            }
        }

        currentElement = ""
        buffer = ""
    }

    private func applyEnclosureAttributes(_ attributes: [String: String]) {
        guard var item = currentItem else {
            return
        }

        for (key, value) in attributes {
            let lower = key.lowercased()
            if lower == "url" {
                item.downloadURL = URL(string: value)
            } else if lower.hasSuffix("shortversionstring") {
                item.shortVersion = value.nilIfBlank
            } else if lower.hasSuffix("version") {
                item.buildVersion = value.nilIfBlank
            }
        }

        currentItem = item
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func extractLikelyVersion() -> String? {
        let pattern = #"v?(\d+(?:\.\d+)+(?:[-+][A-Za-z0-9._-]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard
            let match = regex.firstMatch(in: self, range: range),
            let versionRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }
        return String(self[versionRange])
    }
}
