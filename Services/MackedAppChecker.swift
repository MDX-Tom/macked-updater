import Foundation

struct MackedAppSearchResult: Hashable, Identifiable {
    var name: String
    var title: String
    var latestVersion: String?
    var detailURL: URL
    var imageURL: URL?
    var summary: String?

    var id: String { detailURL.absoluteString }
}

struct MackedAppDetail: Hashable {
    var name: String
    var title: String
    var latestVersion: String?
    var pageURL: URL
    var downloadURL: URL?
    var loginURL: URL
    var officialPageURL: URL?
    var officialDownloadURL: URL?
    var officialSourceName: String?
    var officialIsFree: Bool?
    var activationMethod: String?
    var modifiedAt: Date?
}

private struct MackedRESTSearchItem: Decodable {
    var title: String
    var url: String
}

private actor MackedLookupCache {
    static let shared = MackedLookupCache()

    private var searchTasks: [String: Task<[MackedAppSearchResult], Error>] = [:]
    private var detailTasks: [String: Task<MackedAppDetail, Error>] = [:]

    func searchResults(
        for query: String,
        loader: @escaping @Sendable () async throws -> [MackedAppSearchResult]
    ) async throws -> [MackedAppSearchResult] {
        let key = query.normalizedForMackedCacheKey
        if let task = searchTasks[key] {
            return try await task.value
        }

        let task = Task {
            try await loader()
        }
        searchTasks[key] = task

        do {
            return try await task.value
        } catch {
            searchTasks.removeValue(forKey: key)
            throw error
        }
    }

    func detail(
        for pageURL: URL,
        loader: @escaping @Sendable () async throws -> MackedAppDetail
    ) async throws -> MackedAppDetail {
        let key = pageURL.absoluteString
        if let task = detailTasks[key] {
            return try await task.value
        }

        let task = Task {
            try await loader()
        }
        detailTasks[key] = task

        do {
            return try await task.value
        } catch {
            detailTasks.removeValue(forKey: key)
            throw error
        }
    }
}

struct MackedAppChecker {
    private let baseURL = URL(string: "https://macked.app")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    func search(query: String) async throws -> [MackedAppSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try await MackedLookupCache.shared.searchResults(for: trimmed) {
            try await searchUncached(query: trimmed)
        }
    }

    private func searchUncached(query trimmed: String) async throws -> [MackedAppSearchResult] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "s", value: trimmed),
            URLQueryItem(name: "type", value: "post")
        ]

        do {
            let restResults = try await searchREST(query: trimmed)
            if !restResults.isEmpty {
                return restResults
            }
        } catch {
            // Fall back to the public HTML search page below. The HTML parser is
            // intentionally kept because the WordPress REST endpoint can be
            // disabled or filtered independently from the website search UI.
        }

        let html = try await loadHTML(from: components.url!)
        return Self.parseSearchResults(html: html, baseURL: baseURL)
    }

    func detail(pageURL: URL) async throws -> MackedAppDetail {
        try await MackedLookupCache.shared.detail(for: pageURL) {
            let html = try await loadHTML(from: pageURL)
            return try Self.parseDetail(html: html, pageURL: pageURL)
        }
    }

    func freshDetail(pageURL: URL) async throws -> MackedAppDetail {
        let html = try await loadHTML(from: pageURL)
        return try Self.parseDetail(html: html, pageURL: pageURL)
    }

    func search(app: InstalledApp, preferredQuery: String? = nil) async throws -> [MackedAppSearchResult] {
        guard !Self.shouldSkipMackedLookup(for: app) else {
            return []
        }

        var queries: [String] = []
        if let preferredQuery, !preferredQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queries.append(preferredQuery)
        }
        queries.append(contentsOf: searchAliases(for: app))

        let uniqueQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isUsefulMackedSearchQuery($0) }
            .uniquedPreservingOrder()
            .prefix(4)

        guard !uniqueQueries.isEmpty else {
            return []
        }

        var resultsByQueryIndex: [Int: [MackedAppSearchResult]] = [:]
        var firstError: Error?
        var successCount = 0

        await withTaskGroup(of: (Int, Result<[MackedAppSearchResult], Error>).self) { group in
            for (index, query) in uniqueQueries.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await search(query: query)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            for await (index, result) in group {
                switch result {
                case .success(let results):
                    successCount += 1
                    resultsByQueryIndex[index] = results
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
        }

        if successCount == 0, let firstError {
            throw firstError
        }

        var allResults: [MackedAppSearchResult] = []
        var seen: Set<String> = []
        for index in uniqueQueries.indices {
            for result in resultsByQueryIndex[index] ?? [] where seen.insert(result.detailURL.absoluteString).inserted {
                allResults.append(result)
            }
        }

        return allResults
    }

    func check(app: InstalledApp, userSource: UserUpdateSource? = nil) async -> AppUpdateInfo? {
        let explicitPageURL = userSource?.mackedAppURL
        let query = userSource?.trimmedMackedSearchQuery ?? app.name
        let knownPageURL = explicitPageURL ?? Self.knownMackedPageURL(for: app)

        let sourceIdentifier = knownPageURL?.absoluteString ?? query
        let source = UpdateSource(
            kind: .mackedApp,
            name: UpdateSourceKind.mackedApp.title,
            identifier: sourceIdentifier,
            pageURL: knownPageURL,
            feedURL: nil
        )

        if knownPageURL == nil, Self.shouldSkipMackedLookup(for: app) {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .unknown,
                source: source,
                officialPageURL: nil,
                downloadURL: nil,
                releaseNotesURL: nil,
                loginURL: loginURL(redirectingTo: baseURL),
                mackedLoginURL: loginURL(redirectingTo: baseURL),
                lastCheckedAt: Date(),
                errorMessage: "Macked.app lookup skipped for Apple or system apps."
            )
        }

        do {
            let pageURL: URL
            if let knownPageURL {
                pageURL = knownPageURL
            } else {
                let results = try await search(app: app, preferredQuery: query)
                guard let best = bestMatch(for: app, in: results) else {
                    return AppUpdateInfo(
                        appID: app.id,
                        currentVersion: app.shortVersion,
                        latestVersion: nil,
                        status: .unknown,
                        source: source,
                        officialPageURL: nil,
                        downloadURL: nil,
                        releaseNotesURL: nil,
                        loginURL: loginURL(redirectingTo: baseURL),
                        mackedLoginURL: loginURL(redirectingTo: baseURL),
                        lastCheckedAt: Date(),
                        errorMessage: "No Macked.app result matched this app."
                    )
                }
                pageURL = best.detailURL
            }

            let detail = try await detail(pageURL: pageURL)
            let status = statusFor(current: app.shortVersion, latest: detail.latestVersion, currentBuild: app.buildVersion)
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: detail.latestVersion,
                status: status,
                source: UpdateSource(
                    kind: .mackedApp,
                    name: UpdateSourceKind.mackedApp.title,
                    identifier: pageURL.absoluteString,
                    pageURL: detail.pageURL,
                    feedURL: nil
                ),
                officialPageURL: detail.officialPageURL,
                officialDownloadURL: detail.officialDownloadURL,
                officialSourceName: detail.officialSourceName,
                officialIsFree: detail.officialIsFree,
                downloadURL: detail.downloadURL,
                releaseNotesURL: detail.pageURL,
                loginURL: detail.loginURL,
                mackedPageURL: detail.pageURL,
                mackedDownloadURL: detail.downloadURL,
                mackedLoginURL: detail.loginURL,
                mackedSourceName: UpdateSourceKind.mackedApp.title,
                mackedLatestVersion: detail.latestVersion,
                lastCheckedAt: Date(),
                errorMessage: status == .unknown ? "Macked.app returned metadata, but the version could not be compared safely." : nil
            )
        } catch {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: source,
                officialPageURL: knownPageURL,
                downloadURL: nil,
                releaseNotesURL: knownPageURL,
                loginURL: loginURL(redirectingTo: knownPageURL ?? baseURL),
                mackedLoginURL: loginURL(redirectingTo: knownPageURL ?? baseURL),
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    static func parseSearchResults(html: String, baseURL: URL) -> [MackedAppSearchResult] {
        let blocks = html.matches(pattern: #"<posts\b[^>]*class=[\"'][^\"']*posts-item[^\"']*[\"'][\s\S]*?</posts>"#)
        let candidates = blocks.isEmpty ? [html] : blocks
        var results: [MackedAppSearchResult] = []
        var seen: Set<String> = []

        for block in candidates {
            guard
                let rawHref = block.firstMatch(pattern: #"href=[\"']([^\"']+\.html[^\"']*)[\"']"#)?.capture(1),
                let detailURL = normalizedURL(rawHref.htmlDecoded, baseURL: baseURL)
            else {
                continue
            }

            guard seen.insert(detailURL.absoluteString).inserted else { continue }

            let heading = block.firstMatch(pattern: #"<h[1-3]\b[^>]*class=[\"'][^\"']*item-heading[^\"']*[\"'][\s\S]*?</h[1-3]>"#)?.capture(0) ?? block
            let rawTitle = searchCardTitle(from: heading).trimmed
            guard !rawTitle.isEmpty else { continue }

            let tooltip = block.firstMatch(pattern: #"data-tippy-content=([\"'])([\s\S]*?)\1"#)?.capture(2).htmlDecoded ?? ""
            let name = value(after: "软件名称", in: tooltip)?.strippingHTML.htmlDecoded.trimmed ?? displayName(from: rawTitle)
            let latestVersion = value(after: "软件版本", in: tooltip)?.strippingHTML.htmlDecoded.trimmed ?? extractLikelyVersion(from: rawTitle)
            let imageRaw = block.firstMatch(pattern: #"<img\b[^>]*(?:data-src|src)=[\"']([^\"']+)[\"']"#)?.capture(1)
            let imageURL = imageRaw.flatMap { normalizedURL($0.htmlDecoded, baseURL: baseURL) }
            let summary = block.firstMatch(pattern: #"</h[1-3]>\s*<div[^>]*>([\s\S]*?)</div>"#)?.capture(1).strippingHTML.htmlDecoded.trimmed

            results.append(
                MackedAppSearchResult(
                    name: name.isEmpty ? rawTitle : name,
                    title: rawTitle,
                    latestVersion: latestVersion,
                    detailURL: detailURL,
                    imageURL: imageURL,
                    summary: summary?.isEmpty == true ? nil : summary
                )
            )
        }

        return results
    }

    static func parseDetail(html: String, pageURL: URL) throws -> MackedAppDetail {
        let canonicalRaw = html.firstMatch(pattern: #"<link\b[^>]*rel=[\"']canonical[\"'][^>]*href=[\"']([^\"']+)[\"']"#)?.capture(1)
        let resolvedPageURL = canonicalRaw.flatMap { normalizedURL($0.htmlDecoded, baseURL: pageURL) } ?? pageURL
        let title = html.metaContent(property: "og:title")
            ?? html.firstMatch(pattern: #"<h1[^>]*>([\s\S]*?)</h1>"#)?.capture(1).strippingHTML.htmlDecoded.trimmed
            ?? resolvedPageURL.lastPathComponent
        let compactTitle = title.components(separatedBy: "|").first?.trimmed ?? title
        let name = displayName(from: compactTitle)
        let latestVersion = extractLikelyVersion(from: compactTitle)
            ?? html.valueFromVisibleInfo(label: "软件版本")
        let downloadRaw = html.firstMatch(pattern: #"href=[\"']([^\"']*zibpay/download\.php[^\"']*)[\"']"#)?.capture(1).htmlDecoded
        let downloadURL = downloadRaw.flatMap { normalizedURL($0, baseURL: resolvedPageURL) }
            ?? directContentDownloadURL(from: html, pageURL: resolvedPageURL)
        let modified = html.metaContent(property: "article:modified_time").flatMap(iso8601Date)

        return MackedAppDetail(
            name: name,
            title: compactTitle,
            latestVersion: latestVersion,
            pageURL: resolvedPageURL,
            downloadURL: downloadURL,
            loginURL: loginURL(redirectingTo: resolvedPageURL),
            officialPageURL: officialPageURL(from: html, pageURL: resolvedPageURL),
            officialDownloadURL: officialDownloadURL(from: officialPageURL(from: html, pageURL: resolvedPageURL)),
            officialSourceName: officialSourceName(from: officialPageURL(from: html, pageURL: resolvedPageURL)),
            officialIsFree: officialFree(from: html),
            activationMethod: html.valueFromVisibleInfo(label: "激活方式"),
            modifiedAt: modified
        )
    }

    static func makeSearchURL(query: String) -> URL {
        var components = URLComponents(string: "https://macked.app")!
        components.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "post")
        ]
        return components.url!
    }

    static func makeLoginURL(redirectingTo url: URL) -> URL {
        loginURL(redirectingTo: url)
    }

    static func shouldSkipMackedLookup(for app: InstalledApp) -> Bool {
        if app.isSystemManagedApp {
            return true
        }
        return false
    }

    static func knownMackedPageURL(for app: InstalledApp) -> URL? {
        let haystack = [
            app.name,
            app.bundleIdentifier ?? "",
            URL(fileURLWithPath: app.installPath).deletingPathExtension().lastPathComponent
        ]
        .joined(separator: " ")
        .normalizedForMackedMatch

        if haystack.contains("adobeactivationtool") || haystack.contains("adobeactivation") {
            return URL(string: "https://macked.app/adobe-activation-tool-crack.html")
        }

        if haystack.contains("itoolabanygo") || haystack.contains("anygo") {
            return URL(string: "https://macked.app/anygo-mac-crack.html")
        }

        return nil
    }

    private func loadHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        if let cookieHeader = await MackedCookieStore.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await Self.session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func searchREST(query: String) async throws -> [MackedAppSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("wp-json/wp/v2/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "subtype", value: "post"),
            URLQueryItem(name: "per_page", value: "10")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        if let cookieHeader = await MackedCookieStore.cookieHeader(for: components.url!) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await Self.session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try Self.parseRESTSearchResults(data: data, baseURL: baseURL)
    }

    static func parseRESTSearchResults(data: Data, baseURL: URL) throws -> [MackedAppSearchResult] {
        let decoder = JSONDecoder()
        let payload = try decoder.decode([MackedRESTSearchItem].self, from: data)
        var seen: Set<String> = []

        return payload.compactMap { item -> MackedAppSearchResult? in
            guard let detailURL = normalizedURL(item.url.htmlDecoded, baseURL: baseURL) else {
                return nil
            }
            guard seen.insert(detailURL.absoluteString).inserted else {
                return nil
            }

            let title = item.title.strippingHTML.htmlDecoded.trimmed
            let name = displayName(from: title)
            return MackedAppSearchResult(
                name: name.isEmpty ? title : name,
                title: title,
                latestVersion: extractLikelyVersion(from: title),
                detailURL: detailURL,
                imageURL: nil,
                summary: nil
            )
        }
    }

    func bestMatch(for app: InstalledApp, in results: [MackedAppSearchResult]) -> MackedAppSearchResult? {
        guard !Self.shouldSkipMackedLookup(for: app) else {
            return nil
        }
        guard !results.isEmpty else { return nil }
        let appNames = matchAliases(for: app)
            .map(\.normalizedForMackedMatch)
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
        let appTokens = Set(matchAliases(for: app).flatMap { $0.mackedMatchTokens }.filter(isHighSignalMackedToken))
        guard !appNames.isEmpty || !appTokens.isEmpty else {
            return nil
        }

        return results
            .map { result -> (MackedAppSearchResult, Int) in
                let resultName = result.name.normalizedForMackedMatch
                let title = result.title.normalizedForMackedMatch
                let slug = result.detailURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "-crack", with: "")
                    .replacingOccurrences(of: "-mac", with: "")
                let slugName = slug.normalizedForMackedMatch
                let resultTokens = Set([result.name, result.title, slug].flatMap { $0.mackedMatchTokens }.filter(isHighSignalMackedToken))

                if appNames.contains(resultName) || appNames.contains(title) || appNames.contains(slugName) {
                    return (result, 100)
                }
                if appNames.contains(where: { $0.count >= 4 && (title.hasPrefix($0) || slugName.hasPrefix($0)) }) {
                    return (result, 88)
                }
                if appNames.contains(where: { $0.count >= 6 && (slugName == $0 || $0 == resultName) }) {
                    return (result, 80)
                }

                let overlap = appTokens.intersection(resultTokens)
                guard !overlap.isEmpty else {
                    return (result, 0)
                }

                let tokenScore: Int
                if appTokens.isEmpty {
                    tokenScore = 0
                } else {
                    tokenScore = Int((Double(overlap.count) / Double(appTokens.count)) * 70.0)
                }

                let importantBonus = overlap.contains("adobe") && overlap.contains("activation") ? 25 : 0
                let exactSingleTokenBonus = overlap.contains { token in
                    token.count >= 4 && (resultName == token || slugName == token || slugName.hasPrefix(token + "mac"))
                } ? 35 : 0
                let overlapCountBonus = overlap.count >= 2 ? 15 : 0
                let extraTokenPenalty = max(0, resultTokens.subtracting(appTokens).count - 4) * 5
                return (result, max(0, tokenScore + importantBonus + exactSingleTokenBonus + overlapCountBonus - extraTokenPenalty))
            }
            .sorted { $0.1 > $1.1 }
            .first { $0.1 >= 50 }?
            .0
    }

    private func statusFor(current: String?, latest: String?, currentBuild: String?) -> UpdateStatus {
        switch VersionComparator.compare(current: current, latest: latest, currentBuild: currentBuild) {
        case .currentOlder:
            return .updateAvailable
        case .equal, .currentNewer:
            return .upToDate
        case .unknown:
            return .unknown
        }
    }
}

private func searchAliases(for app: InstalledApp) -> [String] {
    var values: [String] = [app.name]
    let fileName = URL(fileURLWithPath: app.installPath).deletingPathExtension().lastPathComponent
    values.append(fileName)
    values.append(contentsOf: knownCompoundAliases(from: [app.name, fileName, app.bundleIdentifier].compactMap { $0 }))

    let nameTokens = Set([app.name, fileName].flatMap { $0.mackedMatchTokens }.filter(isHighSignalMackedToken))

    if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.lowercased().hasPrefix("com.apple.") {
        let parts = bundleIdentifier.split(separator: ".").map(String.init)
        if let last = parts.last, isHighSignalMackedToken(last) {
            values.append(last)
        }
        if parts.count >= 2 {
            let suffix = parts.suffix(2).joined(separator: " ")
            let suffixTokens = suffix.mackedMatchTokens.filter(isHighSignalMackedToken)
            if !suffixTokens.isEmpty && suffixTokens.count <= 3 {
                values.append(suffix)
            }
        }
    }

    let tokens = nameTokens
    if tokens.contains("adobe") {
        values.append("Adobe")
    }
    if tokens.contains("activation") || tokens.contains("activate") {
        values.append("Activation Tool")
    }
    if tokens.contains("adobe") && (tokens.contains("activation") || tokens.contains("activate") || tokens.contains("tool")) {
        values.insert("Adobe Activation Tool", at: 0)
    }

    return values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && isUsefulMackedSearchQuery($0) }
        .uniquedPreservingOrder()
}

private func matchAliases(for app: InstalledApp) -> [String] {
    var values: [String] = [app.name]
    let fileName = URL(fileURLWithPath: app.installPath).deletingPathExtension().lastPathComponent
    values.append(fileName)
    values.append(contentsOf: knownCompoundAliases(from: [app.name, fileName, app.bundleIdentifier].compactMap { $0 }))

    if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.lowercased().hasPrefix("com.apple.") {
        let parts = bundleIdentifier.split(separator: ".").map(String.init)
        if let last = parts.last, isHighSignalMackedToken(last) {
            values.append(last)
        }
    }

    return values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .uniquedPreservingOrder()
}

private func knownCompoundAliases(from values: [String]) -> [String] {
    let normalized = values
        .map(\.normalizedForMackedMatch)
        .joined(separator: " ")

    var aliases: [String] = []

    if normalized.contains("adobeactivation")
        || (normalized.contains("adobe") && (normalized.contains("activation") || normalized.contains("activate"))) {
        aliases.append("Adobe Activation Tool")
        aliases.append("Adobe Activation")
    }

    if normalized.contains("itoolabanygo") || normalized.contains("anygo") {
        aliases.append("AnyGo")
    }

    return aliases.uniquedPreservingOrder()
}

private let genericMackedMatchTokens: Set<String> = [
    "com", "org", "net", "io", "co", "app", "apps", "mac", "macos", "osx",
    "apple", "inc", "llc", "ltd", "corp", "company", "software", "technology",
    "technologies", "studio", "studios", "launcher", "launch", "store", "connect",
    "desktop", "remote", "automate", "automation", "helper", "agent", "service",
    "services", "menu", "menus", "manager", "utility", "utilities", "tool", "tools",
    "installer", "updater", "update", "download", "downloader", "client", "server",
    "mobile", "phone", "iphone", "ipad", "ios", "android"
]

private func isHighSignalMackedToken(_ rawToken: String) -> Bool {
    let token = rawToken.lowercased()
        .replacingOccurrences(of: #"\.app$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: "", options: .regularExpression)
    guard token.count >= 3 else {
        return false
    }
    guard !genericMackedMatchTokens.contains(token) else {
        return false
    }
    guard token.rangeOfCharacter(from: .decimalDigits) == nil || token.rangeOfCharacter(from: .letters) != nil else {
        return false
    }
    return true
}

private func isUsefulMackedSearchQuery(_ query: String) -> Bool {
    let tokens = query.mackedMatchTokens.filter(isHighSignalMackedToken)
    if tokens.isEmpty {
        return false
    }
    if tokens.count == 1, let token = tokens.first {
        return token.count >= 4 || token.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil
    }
    return true
}

private func searchCardTitle(from heading: String) -> String {
    let patterns = [
        #"data-tippy-content=(['"])[\s\S]*?\1\s*>([^<]*)</a>"#,
        #"<a\b(?=[\s\S]*?href=['"][^'"]+\.html)[\s\S]*?>([^<]*)</a>"#
    ]

    for pattern in patterns {
        if let title = heading.firstMatch(pattern: pattern)?.capture(2).strippingHTML.htmlDecoded.trimmed, !title.isEmpty {
            return title
        }
        if let title = heading.firstMatch(pattern: pattern)?.capture(1).strippingHTML.htmlDecoded.trimmed, !title.isEmpty {
            return title
        }
    }

    return heading.strippingHTML.htmlDecoded.trimmed
}

private func loginURL(redirectingTo url: URL) -> URL {
    var components = URLComponents(string: "https://macked.app/user-sign")!
    components.queryItems = [
        URLQueryItem(name: "tab", value: "signin"),
        URLQueryItem(name: "redirect_to", value: url.absoluteString)
    ]
    return components.url!
}

private func normalizedURL(_ rawValue: String, baseURL: URL) -> URL? {
    let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    if raw.hasPrefix("//") {
        return URL(string: "https:\(raw)")
    }
    if let absolute = URL(string: raw), absolute.scheme != nil {
        return absolute
    }
    return URL(string: raw, relativeTo: baseURL)?.absoluteURL
}

private func displayName(from title: String) -> String {
    let cleanTitle = title.replacingOccurrences(of: "–", with: "-")
    if let version = extractLikelyVersion(from: cleanTitle), let range = cleanTitle.range(of: version) {
        return String(cleanTitle[..<range.lowerBound]).trimmed
    }
    return cleanTitle.components(separatedBy: "-").first?.trimmed ?? cleanTitle.trimmed
}

private func extractLikelyVersion(from value: String) -> String? {
    value.firstMatch(pattern: #"(?<![A-Za-z0-9])v?(\d+(?:[._]\d+)+(?:[-+][A-Za-z0-9._-]+)?)"#)?.capture(1).replacingOccurrences(of: "_", with: ".")
}

private func value(after label: String, in html: String) -> String? {
    guard let range = html.range(of: label) else { return nil }
    let tail = String(html[range.upperBound...])
    return tail.firstMatch(pattern: #"<span\b[^>]*class=[\"'][^\"']*attr-value[^\"']*[\"'][^>]*>([\s\S]*?)</span>"#)?.capture(1)
}

private func officialPageURL(from html: String, pageURL: URL) -> URL? {
    guard let valueHTML = value(after: "软件官网", in: html)?.htmlDecoded else { return nil }
    let href = valueHTML.firstMatch(pattern: #"href\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))"#)
    let raw = href?.capture(1).nilIfEmpty ?? href?.capture(2).nilIfEmpty ?? href?.capture(3).nilIfEmpty
    return raw.flatMap { normalizedURL($0, baseURL: pageURL) }
}

private func officialDownloadURL(from officialPageURL: URL?) -> URL? {
    guard let officialPageURL, let host = officialPageURL.host?.lowercased() else {
        return nil
    }
    if host == "github.com" || host.hasSuffix(".github.com") {
        let parts = officialPageURL.path.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return URL(string: "https://github.com/\(parts[0])/\(parts[1])/releases/latest")
        }
    }
    return officialPageURL
}

private func officialSourceName(from officialPageURL: URL?) -> String? {
    guard let host = officialPageURL?.host?.lowercased() else { return nil }
    if host == "github.com" || host.hasSuffix(".github.com") {
        return "GitHub"
    }
    if host.contains("apps.apple.com") {
        return "Mac App Store"
    }
    return host
}

private func officialFree(from html: String) -> Bool? {
    let method = html.valueFromVisibleInfo(label: "激活方式")?.lowercased()
    let pageText = method ?? ""
    if pageText.contains("开源") || pageText.contains("免费") || pageText.contains("free") || pageText.contains("open source") {
        return true
    }
    if pageText.contains("付费") || pageText.contains("订阅") || pageText.contains("paid") || pageText.contains("trial") {
        return false
    }
    return nil
}

private func directContentDownloadURL(from html: String, pageURL: URL) -> URL? {
    let section = directDownloadSection(from: html)
    let candidates = downloadURLCandidates(in: section, baseURL: pageURL)
    return candidates.first
}

private func directDownloadSection(from html: String) -> String {
    guard let start = html.range(of: "直链下载") ?? html.range(of: "直接下载") ?? html.range(of: "Download") else {
        return html
    }

    let tail = String(html[start.upperBound...])
    let endMarkers = ["网盘下载", "THE END", "相关文章", "猜你喜欢", "</article>"]
    let endIndex = endMarkers
        .compactMap { tail.range(of: $0)?.lowerBound }
        .min()

    if let endIndex {
        return String(tail[..<endIndex])
    }

    return tail
}

private func downloadURLCandidates(in html: String, baseURL: URL) -> [URL] {
    struct Candidate {
        var url: URL
        var score: Int
    }

    var candidates: [Candidate] = []
    var seen: Set<String> = []

    func add(_ rawValue: String, contextScore: Int = 0) {
        let decoded = rawValue.htmlDecoded
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = normalizedURL(decoded, baseURL: baseURL),
            isUsableDownloadURL(url, pageURL: baseURL),
            seen.insert(url.absoluteString).inserted
        else {
            return
        }
        candidates.append(Candidate(url: url, score: scoreDownloadURL(url) + contextScore))
    }

    let anchorPatterns = [
        #"<a\b[^>]*href\s*=\s*"([^"]+)"[^>]*>([\s\S]*?)</a>"#,
        #"<a\b[^>]*href\s*=\s*'([^']+)'[^>]*>([\s\S]*?)</a>"#,
        #"<a\b[^>]*href\s*=\s*([^\s>]+)[^>]*>([\s\S]*?)</a>"#
    ]
    for pattern in anchorPatterns {
        for match in html.regexMatches(pattern: pattern) {
            let label = match.capture(2).strippingHTML.htmlDecoded.lowercased()
            var contextScore = 0
            if label.contains("安装包") || label.contains("installer") || label.contains("install") || label.contains("download") || label.contains("下载") {
                contextScore += 40
            }
            if label.contains("激活") || label.contains("activation") || label.contains("activate") || label.contains("tool") || label.contains("工具") {
                contextScore -= 35
            }
            add(match.capture(1), contextScore: contextScore)
        }
    }

    let attributePatterns = [
        #"\b(?:href|data-url|data-href|data-download|data-link)\s*=\s*"([^"]+)""#,
        #"\b(?:href|data-url|data-href|data-download|data-link)\s*=\s*'([^']+)'"#
    ]
    for pattern in attributePatterns {
        for match in html.regexMatches(pattern: pattern) {
            add(match.capture(1))
        }
    }

    for match in html.regexMatches(pattern: #"https?:\\?/\\?/[^\s"'<>\\]+"#) {
        add(match.capture(0))
    }

    return candidates.sorted { left, right in
        left.score > right.score
    }.map(\.url)
}

private func isUsableDownloadURL(_ url: URL, pageURL: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return false
    }

    let absolute = url.absoluteString.lowercased()
    if absolute.contains("javascript:")
        || absolute.contains("#")
        || absolute.contains("/user-sign")
        || absolute.contains("signin")
        || absolute.contains("login")
        || absolute.contains("logout")
        || absolute.contains("wp-login")
        || absolute.contains("vip")
        || absolute.contains("author/")
        || absolute.contains("tag/")
        || absolute.contains("category/")
        || absolute == pageURL.absoluteString.lowercased() {
        return false
    }

    let ext = url.pathExtension.lowercased()
    let host = url.host?.lowercased() ?? ""
    if host.contains("macked.app"), url.path.lowercased().contains("/dl/") {
        return true
    }
    if host.contains("macked.app"), absolute.contains("zibpay") || absolute.contains("download") {
        return true
    }
    if isWebAssetExtension(ext) {
        return false
    }
    let downloadableExtensions: Set<String> = [
        "dmg", "iso", "pkg", "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2",
        "app", "ipa", "exe", "msi"
    ]
    if downloadableExtensions.contains(ext) {
        return true
    }

    if host.contains("macked.app") {
        return absolute.contains("wp-content/uploads") && !isWebAssetExtension(ext)
    }

    return true
}

private func isWebAssetExtension(_ ext: String) -> Bool {
    [
        "svg", "png", "jpg", "jpeg", "gif", "webp", "avif", "ico",
        "css", "js", "map", "woff", "woff2", "ttf", "otf", "eot",
        "html", "htm", "php"
    ].contains(ext)
}

private func scoreDownloadURL(_ url: URL) -> Int {
    let ext = url.pathExtension.lowercased()
    let absolute = url.absoluteString.lowercased()
    if ["dmg", "iso", "pkg", "zip"].contains(ext) {
        return 100
    }
    if ["rar", "7z", "tar", "gz", "tgz", "xz"].contains(ext) {
        return 90
    }
    if absolute.contains("/dl/") {
        return 86
    }
    if absolute.contains("download") {
        return 80
    }
    if absolute.contains("pan.") || absolute.contains("drive.") || absolute.contains("cloud") {
        return 40
    }
    return 50
}

private func iso8601Date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private struct RegexMatch {
    let source: String
    let result: NSTextCheckingResult

    func capture(_ index: Int) -> String {
        guard index < result.numberOfRanges, let range = Range(result.range(at: index), in: source) else {
            return ""
        }
        return String(source[range])
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var htmlDecoded: String {
        var value = self
        let replacements = [
            "&amp;": "&",
            "&#038;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value.decodingNumericHTMLEntities
    }

    var decodingNumericHTMLEntities: String {
        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        var result = self
        for match in regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self)).reversed() {
            guard
                let fullRange = Range(match.range(at: 0), in: self),
                let numberRange = Range(match.range(at: 1), in: self)
            else { continue }
            let raw = String(self[numberRange])
            let scalarValue: UInt32?
            if raw.lowercased().hasPrefix("x") {
                scalarValue = UInt32(raw.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(raw, radix: 10)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return result
    }

    func matches(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            Range(match.range(at: 0), in: self).map { String(self[$0]) }
        }
    }

    func firstMatch(pattern: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return RegexMatch(source: self, result: match)
    }

    func regexMatches(pattern: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map {
            RegexMatch(source: self, result: $0)
        }
    }

    func attributeValue(named name: String) -> String? {
        firstMatch(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*([\"'])([\s\S]*?)\1"#)?.capture(2)
    }

    func metaContent(property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta\b(?=[^>]*(?:property|name)=[\"']"# + escaped + #"[\"'])(?=[^>]*content=[\"']([^\"']*)[\"'])[^>]*>"#,
            #"<meta\b(?=[^>]*content=[\"']([^\"']*)[\"'])(?=[^>]*(?:property|name)=[\"']"# + escaped + #"[\"'])[^>]*>"#
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern: pattern)?.capture(1).htmlDecoded.trimmed, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func valueFromVisibleInfo(label: String) -> String? {
        value(after: label, in: self)?.strippingHTML.htmlDecoded.trimmed
    }

    var normalizedForMackedMatch: String {
        lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedForMackedCacheKey: String {
        lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var mackedMatchTokens: [String] {
        let stopWords: Set<String> = [
            "mac", "app", "for", "the", "pro", "lite", "desktop", "helper",
            "crack", "破解版", "激活", "工具", "补丁"
        ]
        let expanded = insertingMackedTokenBoundaries
        let normalized = expanded.lowercased()
            .replacingOccurrences(of: ".app", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: " ", options: .regularExpression)
        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
            .uniquedPreservingOrder()
    }

    var insertingMackedTokenBoundaries: String {
        var value = self
        value = value.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(adobe)(activation)"#, with: "$1 $2", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(activation)(tool)"#, with: "$1 $2", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(itoolab)(anygo)"#, with: "$1 $2", options: .regularExpression)
        return value
    }
}
