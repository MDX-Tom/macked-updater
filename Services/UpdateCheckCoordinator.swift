import Foundation

struct UpdateCheckCoordinator {
    private let sparkleChecker = SparkleAppcastChecker()
    private let homebrewChecker: HomebrewCaskChecker
    private let macAppStoreChecker = MacAppStoreChecker()
    private let adobeOfficialChecker = AdobeOfficialChecker()
    private let githubChecker = GitHubReleaseChecker()
    private let authorizedCatalogChecker = AuthorizedUpdateCatalogChecker()
    private let mackedChecker = MackedAppChecker()
    private let websiteResolver = OfficialWebsiteResolver()

    init(homebrewChecker: HomebrewCaskChecker = HomebrewCaskChecker()) {
        self.homebrewChecker = homebrewChecker
    }

    func check(app: InstalledApp, userSource: UserUpdateSource?, settings: AppSettings) async -> AppUpdateInfo {
        await checkOfficial(app: app, userSource: userSource, settings: settings)
    }

    func checkOfficial(app: InstalledApp, userSource: UserUpdateSource?, settings: AppSettings) async -> AppUpdateInfo {
        let result = await checkOfficialSources(
            app: app,
            userSource: validated(userSource: userSource),
            settings: settings
        )
        return normalizedOfficialInfo(result)
    }

    func checkMacked(app: InstalledApp, userSource: UserUpdateSource?, settings: AppSettings) async -> AppUpdateInfo? {
        await checkMackedIfEnabled(
            app: app,
            userSource: validated(userSource: userSource),
            settings: settings
        )
    }

    func merge(app: InstalledApp, official: AppUpdateInfo, macked: AppUpdateInfo?) -> AppUpdateInfo {
        mergeOfficialAndMacked(app: app, official: official, macked: macked)
    }

    private func validated(userSource: UserUpdateSource?) -> UserUpdateSource? {
        var activeUserSource = userSource
        if let userSource, userSource.hasAnySource {
            let validationMessages = SourceValidation.validationMessages(for: userSource)
            if !validationMessages.isEmpty {
                activeUserSource = nil
            }
        }
        return activeUserSource
    }

    private func checkOfficialSources(app: InstalledApp, userSource: UserUpdateSource?, settings: AppSettings) async -> AppUpdateInfo {
        if let userSource, userSource.hasAnySource, let result = await checkUserSource(app: app, userSource: userSource, settings: settings) {
            return result
        }

        async let sparkleTask = checkSparkleIfAvailable(app: app, settings: settings)
        async let homebrewTask = checkHomebrewIfAvailable(app: app, settings: settings)
        async let macAppStoreTask = checkMacAppStoreIfAvailable(app: app)
        async let adobeTask = checkAdobeOfficialIfAvailable(app: app)

        let sparkleResult = await sparkleTask
        let homebrewResult = await homebrewTask
        let macAppStoreResult = await macAppStoreTask
        let adobeResult = await adobeTask
        let priorityResults = [sparkleResult, homebrewResult, macAppStoreResult, adobeResult]
        let firstError = priorityResults.compactMap { $0 }.first { $0.status == .error }

        for result in priorityResults.compactMap({ $0 }) where result.status != .error {
            return result
        }

        return firstError ?? websiteResolver.unresolvedInfo(for: app)
    }

    private func checkMackedIfEnabled(app: InstalledApp, userSource: UserUpdateSource?, settings: AppSettings) async -> AppUpdateInfo? {
        guard settings.checkMackedApp else {
            return nil
        }
        return await mackedChecker.check(app: app, userSource: userSource)
    }

    private func checkSparkleIfAvailable(app: InstalledApp, settings: AppSettings) async -> AppUpdateInfo? {
        guard settings.checkSparkleAppcast, let feedURL = app.sparkleFeedURL else {
            return nil
        }
        return await sparkleChecker.check(app: app, feedURL: feedURL)
    }

    private func checkHomebrewIfAvailable(app: InstalledApp, settings: AppSettings) async -> AppUpdateInfo? {
        guard settings.checkHomebrewCask else {
            return nil
        }
        return await homebrewChecker.check(app: app)
    }

    private func checkMacAppStoreIfAvailable(app: InstalledApp) async -> AppUpdateInfo? {
        await macAppStoreChecker.check(app: app)
    }

    private func checkAdobeOfficialIfAvailable(app: InstalledApp) async -> AppUpdateInfo? {
        await adobeOfficialChecker.check(app: app)
    }

    private func checkUserSource(app: InstalledApp, userSource: UserUpdateSource, settings: AppSettings) async -> AppUpdateInfo? {
        var firstError: AppUpdateInfo?

        if let catalogURL = userSource.authorizedCatalogURL {
            let result = await authorizedCatalogChecker.check(
                app: app,
                catalogURL: catalogURL,
                preferredPageURL: userSource.officialPageURL
            )
            if result.status != .error {
                return result
            }
            firstError = firstError ?? result
        }

        if settings.checkSparkleAppcast, let appcastURL = userSource.appcastURL {
            let result = await sparkleChecker.check(
                app: app,
                feedURL: appcastURL,
                sourceKind: .userConfigured,
                sourceName: "User Appcast",
                preferredPageURL: userSource.officialPageURL
            )
            if result.status != .error {
                return result
            }
            firstError = firstError ?? result
        }

        if let githubURL = userSource.githubReleasesURL {
            let result = await githubChecker.check(app: app, releasesURL: githubURL, preferredPageURL: userSource.officialPageURL)
            if result.status != .error {
                return result
            }
            firstError = firstError ?? result
        }

        if settings.checkHomebrewCask, let caskName = userSource.trimmedHomebrewCaskName {
            let result = await homebrewChecker.check(app: app, forcedCaskName: caskName)
            if let result, result.status != .error {
                return result
            }
            if let result {
                firstError = firstError ?? result
            }
        }

        if let officialPageURL = userSource.officialPageURL {
            return AppUpdateInfo(
                appID: app.id,
                currentVersion: app.shortVersion,
                latestVersion: nil,
                status: .unknown,
                source: UpdateSource(
                    kind: .userConfigured,
                    name: "User Official Page",
                    identifier: officialPageURL.absoluteString,
                    pageURL: officialPageURL,
                    feedURL: userSource.appcastURL
                ),
                officialPageURL: officialPageURL,
                downloadURL: nil,
                releaseNotesURL: nil,
                lastCheckedAt: Date(),
                errorMessage: nil
            )
        }

        return firstError
    }

    private func mergeOfficialAndMacked(app: InstalledApp, official: AppUpdateInfo, macked: AppUpdateInfo?) -> AppUpdateInfo {
        guard let macked else {
            return normalizedOfficialInfo(official)
        }

        var merged = normalizedOfficialInfo(official)
        let mackedHasResult = macked.mackedPageURL != nil
            || macked.source?.pageURL != nil
            || macked.downloadURL != nil
            || macked.mackedDownloadURL != nil
            || macked.latestVersion != nil

        merged.mackedPageURL = macked.mackedPageURL ?? (macked.source?.kind == .mackedApp ? macked.officialPageURL ?? macked.source?.pageURL : nil)
        merged.mackedDownloadURL = macked.mackedDownloadURL ?? macked.downloadURL
        merged.mackedLoginURL = macked.mackedLoginURL ?? macked.loginURL
        merged.mackedSourceName = mackedHasResult ? UpdateSourceKind.mackedApp.title : nil
        merged.mackedLatestVersion = mackedHasResult ? macked.latestVersion : nil

        if merged.officialPageURL == nil {
            merged.officialPageURL = macked.officialPageURL
        }
        if merged.officialDownloadURL == nil {
            merged.officialDownloadURL = macked.officialDownloadURL
        }
        if merged.officialSourceName == nil {
            merged.officialSourceName = macked.officialSourceName
        }
        if merged.officialIsFree == nil {
            merged.officialIsFree = macked.officialIsFree
        }

        let officialHasVersionSignal = merged.officialLatestVersion != nil
            && merged.status != .unknown
            && merged.status != .error

        if !officialHasVersionSignal, mackedHasResult {
            merged.latestVersion = macked.latestVersion ?? merged.latestVersion
            merged.officialLatestVersion = merged.officialLatestVersion ?? macked.latestVersion
            if merged.officialPageURL == nil || merged.source?.kind == .manualSearch {
                merged.officialPageURL = macked.officialPageURL ?? merged.mackedPageURL ?? macked.source?.pageURL
            }
            if merged.officialDownloadURL == nil {
                merged.officialDownloadURL = macked.officialDownloadURL ?? merged.mackedDownloadURL ?? macked.downloadURL
            }
            if merged.officialSourceName == nil || merged.source?.kind == .manualSearch || merged.source == nil {
                merged.officialSourceName = UpdateSourceKind.mackedApp.title
            }
            merged.status = macked.status
            merged.source = macked.source ?? merged.source
            if macked.status != .error {
                merged.errorMessage = nil
            }
        }

        merged.downloadURL = merged.officialDownloadURL ?? merged.mackedDownloadURL ?? merged.downloadURL
        merged.loginURL = merged.mackedLoginURL

        if official.status == .error && mackedHasResult && macked.status != .error {
            merged.errorMessage = nil
        }
        if merged.lastCheckedAt == nil || (macked.lastCheckedAt ?? .distantPast) > (merged.lastCheckedAt ?? .distantPast) {
            merged.lastCheckedAt = macked.lastCheckedAt
        }

        return merged
    }

    private func normalizedOfficialInfo(_ info: AppUpdateInfo) -> AppUpdateInfo {
        var normalized = info
        if normalized.source?.kind != .mackedApp {
            normalized.officialLatestVersion = normalized.officialLatestVersion ?? normalized.latestVersion
            normalized.officialSourceName = normalized.officialSourceName ?? normalized.source?.name
            normalized.officialDownloadURL = normalized.officialDownloadURL ?? normalized.downloadURL
            normalized.officialIsFree = normalized.officialIsFree ?? inferredFreeStatus(for: normalized.source)
            normalized.downloadURL = normalized.officialDownloadURL
        } else {
            normalized.mackedLatestVersion = normalized.mackedLatestVersion ?? normalized.latestVersion
        }
        return normalized
    }

    private func inferredFreeStatus(for source: UpdateSource?) -> Bool? {
        switch source?.kind {
        case .githubReleases:
            return true
        case .macAppStore, .sparkleAppcast, .homebrewCask, .officialWebsite, .authorizedCatalog, .manualSearch, .userConfigured, .mackedApp, nil:
            return nil
        }
    }
}
