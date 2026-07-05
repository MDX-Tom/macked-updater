import Foundation

struct AdobeOfficialChecker {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    func check(app: InstalledApp) async -> AppUpdateInfo? {
        guard let product = AdobeProduct.match(app: app) else {
            return nil
        }

        do {
            let html = try await loadHTML(from: product.releaseNotesURL)
            let latestVersion = Self.extractLatestVersion(from: html, product: product) ?? product.fallbackLatestVersion
            let status = statusFor(current: app.shortVersion, latest: latestVersion, currentBuild: app.buildVersion)
            let source = UpdateSource(
                kind: .officialWebsite,
                name: "Adobe Help Center: \(product.displayName)",
                identifier: product.id,
                pageURL: product.releaseNotesURL,
                feedURL: nil
            )

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: latestVersion,
                status: status,
                source: source,
                officialPageURL: product.productURL,
                officialDownloadURL: product.downloadURL,
                officialSourceName: "Adobe Help Center",
                officialIsFree: product.isFree,
                downloadURL: product.downloadURL,
                releaseNotesURL: product.releaseNotesURL,
                lastCheckedAt: Date(),
                errorMessage: latestVersion == nil ? "Adobe official page was found, but the latest version could not be parsed safely." : nil
            )
        } catch {
            if let fallbackLatestVersion = product.fallbackLatestVersion {
                let status = statusFor(current: app.shortVersion, latest: fallbackLatestVersion, currentBuild: app.buildVersion)
                return AppUpdateInfo(
                    appID: app.id,
                    currentVersion: app.shortVersion,
                    latestVersion: fallbackLatestVersion,
                    status: status,
                    source: UpdateSource(
                        kind: .officialWebsite,
                        name: "Adobe Help Center: \(product.displayName)",
                        identifier: product.id,
                        pageURL: product.releaseNotesURL,
                        feedURL: nil
                    ),
                    officialPageURL: product.productURL,
                    officialDownloadURL: product.downloadURL,
                    officialSourceName: "Adobe Help Center",
                    officialIsFree: product.isFree,
                    downloadURL: product.downloadURL,
                    releaseNotesURL: product.releaseNotesURL,
                    lastCheckedAt: Date(),
                    errorMessage: "Used bundled Adobe release-note fallback because the official page could not be loaded in time."
                )
            }

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(
                    kind: .officialWebsite,
                    name: "Adobe Help Center: \(product.displayName)",
                    identifier: product.id,
                    pageURL: product.releaseNotesURL,
                    feedURL: nil
                ),
                officialPageURL: product.productURL,
                officialDownloadURL: product.downloadURL,
                officialSourceName: "Adobe Help Center",
                officialIsFree: product.isFree,
                downloadURL: product.downloadURL,
                releaseNotesURL: product.releaseNotesURL,
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    static func extractLatestVersion(from html: String, product: AdobeProduct) -> String? {
        let text = html.htmlTextForAdobeVersionParsing
        let productNames = [product.displayName] + product.aliases
        let versionPattern = #"([0-9]{1,2}(?:\.[0-9]{1,3}){1,3})"#

        let focusedPatterns: [String] = productNames.flatMap { name in
            let escaped = NSRegularExpression.escapedPattern(for: name)
            return [
                #"(?i)latest(?:\s+and\s+most\s+current)?\s+version\s+of\s+"# + escaped + #"[^0-9]{0,120}"# + versionPattern,
                #"(?i)current\s+version\s+of\s+"# + escaped + #"[^0-9]{0,120}"# + versionPattern,
                #"(?i)"# + escaped + #"[^\n]{0,100}\(\s*version\s+"# + versionPattern + #"\s*\)"#,
                #"(?i)"# + escaped + #"[^\n]{0,100}\b"# + versionPattern + #"\b"#
            ]
        }

        let generalPatterns = [
            #"(?i)latest(?:\s+and\s+most\s+current)?\s+version[^0-9]{0,140}"# + versionPattern,
            #"(?i)current\s+version[^0-9]{0,140}"# + versionPattern,
            #"(?i)(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+20[0-9]{2}\s*(?:release)?\s*\(\s*version\s+"# + versionPattern + #"\s*\)"#,
            #"(?i)\(\s*version\s+"# + versionPattern + #"\s*\)"#,
            #"(?i)\bv\s*"# + versionPattern + #"\b"#
        ]

        for pattern in focusedPatterns + generalPatterns {
            if let version = text.firstAdobeVersionMatch(pattern: pattern) {
                return version
            }
        }

        return nil
    }

    private func loadHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,zh-CN;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await Self.session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func statusFor(current: String?, latest: String?, currentBuild: String?) -> UpdateStatus {
        switch VersionComparator.compare(current: current, latest: latest, currentBuild: currentBuild) {
        case .currentOlder:
            return .updateAvailable
        case .equal, .currentNewer:
            return .upToDate
        case .unknown:
            return latest == nil ? .unknown : .unknown
        }
    }
}

struct AdobeProduct: Hashable {
    var id: String
    var displayName: String
    var aliases: [String]
    var releaseNotesURL: URL
    var productURL: URL
    var downloadURL: URL
    var isFree: Bool?
    var fallbackLatestVersion: String? = nil

    static let products: [AdobeProduct] = [
        AdobeProduct(
            id: "photoshop",
            displayName: "Photoshop",
            aliases: ["Adobe Photoshop", "Photoshop 2026", "PHSP"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/photoshop/desktop/whats-new/photoshop-on-desktop-release-notes.html")!,
            productURL: URL(string: "https://www.adobe.com/products/photoshop.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false,
            fallbackLatestVersion: "27.8"
        ),
        AdobeProduct(
            id: "lightroom-classic",
            displayName: "Lightroom Classic",
            aliases: ["Adobe Lightroom Classic", "LightroomClassic", "Lightroom Classic CC", "LTRM"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/lightroom-classic/help/whats-new/release-notes.html")!,
            productURL: URL(string: "https://www.adobe.com/products/photoshop-lightroom-classic.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false,
            fallbackLatestVersion: "15.4.1"
        ),
        AdobeProduct(
            id: "audition",
            displayName: "Audition",
            aliases: ["Adobe Audition", "Audition 2026", "AUDT"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/audition/desktop/introduction/audition-releasenotes.html")!,
            productURL: URL(string: "https://www.adobe.com/products/audition.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false,
            fallbackLatestVersion: "26.3"
        ),
        AdobeProduct(
            id: "premiere-pro",
            displayName: "Premiere Pro",
            aliases: ["Adobe Premiere Pro", "Premiere"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/premiere/desktop/whats-new/release-notes.html")!,
            productURL: URL(string: "https://www.adobe.com/products/premiere.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false
        ),
        AdobeProduct(
            id: "after-effects",
            displayName: "After Effects",
            aliases: ["Adobe After Effects"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/after-effects/using/whats-new.html")!,
            productURL: URL(string: "https://www.adobe.com/products/aftereffects.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false
        ),
        AdobeProduct(
            id: "illustrator",
            displayName: "Illustrator",
            aliases: ["Adobe Illustrator"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/illustrator/using/whats-new.html")!,
            productURL: URL(string: "https://www.adobe.com/products/illustrator.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false
        ),
        AdobeProduct(
            id: "indesign",
            displayName: "InDesign",
            aliases: ["Adobe InDesign"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/indesign/using/whats-new.html")!,
            productURL: URL(string: "https://www.adobe.com/products/indesign.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: false
        ),
        AdobeProduct(
            id: "dng-converter",
            displayName: "DNG Converter",
            aliases: ["Adobe DNG Converter", "DNGConverter"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/camera-raw/using/adobe-dng-converter.html")!,
            productURL: URL(string: "https://helpx.adobe.com/camera-raw/using/adobe-dng-converter.html")!,
            downloadURL: URL(string: "https://helpx.adobe.com/camera-raw/using/adobe-dng-converter.html")!,
            isFree: true,
            fallbackLatestVersion: "17.5.1"
        ),
        AdobeProduct(
            id: "creative-cloud",
            displayName: "Creative Cloud",
            aliases: ["Adobe Creative Cloud", "Creative Cloud Desktop App", "AdobeCreativeCloud"],
            releaseNotesURL: URL(string: "https://helpx.adobe.com/creative-cloud/release-note/cc-release-notes.html")!,
            productURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            downloadURL: URL(string: "https://www.adobe.com/creativecloud/desktop-app.html")!,
            isFree: true
        )
    ]

    static func match(app: InstalledApp) -> AdobeProduct? {
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.name.lowercased()
        let path = app.installPath.lowercased()
        let haystack = [bundle, name, path].joined(separator: " ")

        if bundle == "app.macked.adobe-activation-tool" || name.contains("activation tool") {
            return nil
        }

        return products.first { product in
            if haystack.contains(product.id.replacingOccurrences(of: "-", with: "")) {
                return true
            }
            if haystack.contains(product.id) {
                return true
            }
            if product.aliases.contains(where: { haystack.contains($0.lowercased().replacingOccurrences(of: " ", with: "")) || haystack.contains($0.lowercased()) }) {
                return true
            }
            return haystack.contains(product.displayName.lowercased())
        }
    }
}

private extension String {
    var htmlTextForAdobeVersionParsing: String {
        var value = self
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let replacements = [
            "&amp;": "&",
            "&#038;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&#8211;": "-",
            "&ndash;": "-",
            "&mdash;": "-"
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstAdobeVersionMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else {
            return nil
        }
        for index in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            guard let captureRange = Range(match.range(at: index), in: self) else {
                continue
            }
            let value = String(self[captureRange])
            if value.range(of: #"^[0-9]{1,2}(?:\.[0-9]{1,3}){1,3}$"#, options: .regularExpression) != nil {
                return value
            }
        }
        return nil
    }
}
