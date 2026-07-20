import Foundation

actor HomebrewCaskChecker {
    private var cachedCasks: [String: HomebrewCaskInfo]?
    private var cachedCasksLoadTask: Task<[String: HomebrewCaskInfo], Error>?
    private var cachedCasksLoadError: Error?
    private let brewURL: URL?

    init() {
        brewURL = Self.findBrewExecutable()
    }

    var isAvailable: Bool {
        brewURL != nil
    }

    func check(app: InstalledApp, forcedCaskName: String? = nil) async -> AppUpdateInfo? {
        guard let brewURL else {
            return nil
        }

        do {
            let cask: HomebrewCaskInfo?
            if let forcedCaskName, !forcedCaskName.isEmpty {
                cask = try await loadInfo(for: forcedCaskName, brewURL: brewURL)
            } else {
                let casks = try await installedCasks(brewURL: brewURL)
                cask = match(app: app, in: casks.values)
            }

            guard let cask else {
                return nil
            }

            let latestVersion = cask.comparableVersion
            let latestBuild = cask.comparableBuildVersion
            let status = statusFor(
                current: app.shortVersion,
                latest: latestVersion,
                currentBuild: app.buildVersion,
                latestBuild: latestBuild
            )
            let source = UpdateSource(
                kind: .homebrewCask,
                name: "Homebrew Cask: \(cask.token)",
                identifier: cask.token,
                pageURL: cask.homepage,
                feedURL: nil
            )

            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: latestVersion,
                latestBuildVersion: latestBuild,
                status: status,
                source: source,
                officialPageURL: cask.homepage,
                downloadURL: nil,
                releaseNotesURL: cask.homepage,
                lastCheckedAt: Date(),
                errorMessage: status == .unknown ? "Homebrew returned a version that could not be compared safely." : nil
            )
        } catch {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .error,
                source: UpdateSource(kind: .homebrewCask, name: UpdateSourceKind.homebrewCask.title, identifier: forcedCaskName, pageURL: nil, feedURL: nil),
                officialPageURL: nil,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }
    }

    private func installedCasks(brewURL: URL) async throws -> [String: HomebrewCaskInfo] {
        if let cachedCasks {
            return cachedCasks
        }

        if let cachedCasksLoadError {
            throw cachedCasksLoadError
        }

        if let cachedCasksLoadTask {
            return try await cachedCasksLoadTask.value
        }

        let task = Task {
            try await Self.loadInstalledCaskInfo(brewURL: brewURL)
        }
        cachedCasksLoadTask = task

        do {
            let casks = try await task.value
            cachedCasks = casks
            cachedCasksLoadTask = nil
            return casks
        } catch {
            cachedCasksLoadTask = nil
            cachedCasksLoadError = error
            throw error
        }
    }

    private static func loadInstalledCaskInfo(brewURL: URL) async throws -> [String: HomebrewCaskInfo] {
        let output = try await ProcessRunner.run(
            executableURL: brewURL,
            arguments: ["info", "--cask", "--json=v2", "--installed"],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        )
        var casks: [String: HomebrewCaskInfo] = [:]
        for info in try Self.parseCaskInfoJSON(output) {
            casks[info.token] = info
        }
        return casks
    }

    private func loadInfo(for token: String, brewURL: URL) async throws -> HomebrewCaskInfo? {
        if let cached = cachedCasks?[token] {
            return cached
        }

        let output = try await ProcessRunner.run(
            executableURL: brewURL,
            arguments: ["info", "--cask", "--json=v2", token],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        )
        return try Self.parseCaskInfoJSON(output).first
    }

    private func match(app: InstalledApp, in casks: Dictionary<String, HomebrewCaskInfo>.Values) -> HomebrewCaskInfo? {
        let appName = app.name.normalizedForMatching
        let bundleIdentifier = app.bundleIdentifier?.normalizedForMatching ?? ""
        let appFileName = URL(fileURLWithPath: app.installPath).lastPathComponent.normalizedForMatching

        return casks.first { cask in
            let token = cask.token.normalizedForMatching
            if token == appName || token == appFileName || bundleIdentifier.contains(token) {
                return true
            }

            if cask.names.contains(where: { $0.normalizedForMatching == appName }) {
                return true
            }

            return cask.appNames.contains { artifactName in
                let normalizedArtifact = artifactName.normalizedForMatching
                return normalizedArtifact == appName || normalizedArtifact == appFileName
            }
        }
    }

    private func statusFor(current: String?, latest: String?, currentBuild: String?, latestBuild: String?) -> UpdateStatus {
        guard latest?.lowercased() != "latest" else {
            return .unknown
        }

        switch VersionComparator.compare(
            current: current,
            latest: latest,
            currentBuild: currentBuild,
            latestBuild: latestBuild
        ) {
        case .currentOlder:
            return .updateAvailable
        case .equal, .currentNewer:
            return .upToDate
        case .unknown:
            return .unknown
        }
    }

    private static func findBrewExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("brew")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func parseCaskInfoJSON(_ json: String) throws -> [HomebrewCaskInfo] {
        guard
            let data = json.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let casks = root["casks"] as? [[String: Any]]
        else {
            return []
        }

        return casks.compactMap(HomebrewCaskInfo.init(json:))
    }
}

struct HomebrewCaskInfo: Hashable {
    var token: String
    var names: [String]
    var version: String
    var homepage: URL?
    var appNames: [String]

    var comparableVersion: String? {
        let first = version.split(separator: ",").first.map(String.init) ?? version
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var comparableBuildVersion: String? {
        let components = version.split(separator: ",", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return nil
        }
        let build = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !build.isEmpty, build.allSatisfy(\.isNumber) else {
            return nil
        }
        return build
    }

    init?(json: [String: Any]) {
        guard let token = json["token"] as? String else {
            return nil
        }

        self.token = token
        if let name = json["name"] as? String {
            names = [name]
        } else if let nameArray = json["name"] as? [String] {
            names = nameArray
        } else {
            names = []
        }
        version = (json["version"] as? String) ?? "Unknown"
        homepage = (json["homepage"] as? String).flatMap(URL.init(string:))
        appNames = Self.collectAppNames(from: json["artifacts"] as Any)
    }

    private static func collectAppNames(from value: Any) -> [String] {
        var names: [String] = []

        func walk(_ item: Any) {
            if let string = item as? String {
                if string.lowercased().hasSuffix(".app") {
                    names.append(string)
                }
                return
            }

            if let array = item as? [Any] {
                array.forEach(walk)
                return
            }

            if let dictionary = item as? [String: Any] {
                for (key, value) in dictionary {
                    if key == "target", let target = value as? String, target.lowercased().hasSuffix(".app") {
                        names.append(target)
                    }
                    walk(value)
                }
            }
        }

        walk(value)
        return Array(Set(names))
    }
}

private extension String {
    var normalizedForMatching: String {
        lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
