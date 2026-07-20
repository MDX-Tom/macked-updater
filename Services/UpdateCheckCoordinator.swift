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
        return normalizedOfficialInfo(result, app: app)
    }

    func checkMacked(
        app: InstalledApp,
        userSource: UserUpdateSource?,
        settings: AppSettings,
        cachedInfo: AppUpdateInfo? = nil
    ) async -> AppUpdateInfo? {
        await checkMackedIfEnabled(
            app: app,
            userSource: validated(userSource: userSource),
            settings: settings,
            cachedInfo: cachedInfo
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

        var firstError: AppUpdateInfo?
        if let sparkleResult = await checkSparkleIfAvailable(app: app, settings: settings) {
            if sparkleResult.status != .error {
                return sparkleResult
            }
            firstError = sparkleResult
        }

        async let homebrewTask = checkHomebrewIfAvailable(app: app, settings: settings)
        async let macAppStoreTask = checkMacAppStoreIfAvailable(app: app)
        async let adobeTask = checkAdobeOfficialIfAvailable(app: app)

        let homebrewResult = await homebrewTask
        let macAppStoreResult = await macAppStoreTask
        let adobeResult = await adobeTask
        let priorityResults = [homebrewResult, macAppStoreResult, adobeResult]
        firstError = firstError ?? priorityResults.compactMap { $0 }.first { $0.status == .error }

        for result in priorityResults.compactMap({ $0 }) where result.status != .error {
            return result
        }

        return firstError ?? websiteResolver.unresolvedInfo(for: app)
    }

    private func checkMackedIfEnabled(
        app: InstalledApp,
        userSource: UserUpdateSource?,
        settings: AppSettings,
        cachedInfo: AppUpdateInfo?
    ) async -> AppUpdateInfo? {
        guard settings.checkMackedApp else {
            return nil
        }
        return await mackedChecker.check(
            app: app,
            userSource: userSource,
            cachedPageURL: cachedInfo?.mackedPageURL
        )
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
            return normalizedOfficialInfo(official, app: app)
        }

        var merged = normalizedOfficialInfo(official, app: app)
        let mackedVersion = trimmedVersion(macked.mackedLatestVersion) ?? trimmedVersion(macked.latestVersion)
        let mackedBuild = trimmedVersion(macked.mackedLatestBuildVersion) ?? trimmedVersion(macked.latestBuildVersion)
        let mackedHasResult = macked.mackedPageURL != nil
            || macked.source?.pageURL != nil
            || macked.downloadURL != nil
            || macked.mackedDownloadURL != nil
            || mackedVersion != nil

        merged.mackedPageURL = macked.mackedPageURL ?? (macked.source?.kind == .mackedApp ? macked.officialPageURL ?? macked.source?.pageURL : nil)
        merged.mackedDownloadURL = macked.mackedDownloadURL ?? macked.downloadURL
        merged.mackedLoginURL = macked.mackedLoginURL ?? macked.loginURL
        merged.mackedSourceName = mackedHasResult ? UpdateSourceKind.mackedApp.title : nil
        merged.mackedLatestVersion = mackedHasResult ? mackedVersion : nil
        merged.mackedLatestBuildVersion = mackedHasResult ? mackedBuild : nil

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
            merged.latestVersion = mackedVersion ?? merged.latestVersion
            merged.latestBuildVersion = mackedBuild ?? merged.latestBuildVersion
            merged.officialLatestVersion = merged.officialLatestVersion ?? mackedVersion
            merged.officialLatestBuildVersion = merged.officialLatestBuildVersion ?? mackedBuild
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

        merged = applyingHighestKnownVersion(for: app, to: merged)
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

    private func normalizedOfficialInfo(_ info: AppUpdateInfo, app: InstalledApp) -> AppUpdateInfo {
        var normalized = info
        if normalized.source?.kind != .mackedApp {
            normalized.officialLatestVersion = normalized.officialLatestVersion ?? normalized.latestVersion
            normalized.officialLatestBuildVersion = normalized.officialLatestBuildVersion ?? normalized.latestBuildVersion
            normalized.officialSourceName = normalized.officialSourceName ?? normalized.source?.name
            if normalized.officialDownloadURL == nil, normalized.downloadURL != normalized.mackedDownloadURL {
                normalized.officialDownloadURL = normalized.downloadURL
            }
            normalized.officialIsFree = normalized.officialIsFree ?? inferredFreeStatus(for: normalized.source)
            normalized.downloadURL = normalized.officialDownloadURL ?? normalized.mackedDownloadURL ?? normalized.downloadURL
        } else {
            normalized.mackedLatestVersion = normalized.mackedLatestVersion ?? normalized.latestVersion
            normalized.mackedLatestBuildVersion = normalized.mackedLatestBuildVersion ?? normalized.latestBuildVersion
        }
        return applyingHighestKnownVersion(for: app, to: normalized)
    }

    private func applyingHighestKnownVersion(for app: InstalledApp, to info: AppUpdateInfo) -> AppUpdateInfo {
        var updated = info
        let officialVersion = trimmedVersion(updated.officialLatestVersion)
            ?? (updated.source?.kind == .mackedApp ? nil : trimmedVersion(updated.latestVersion))
        let officialBuild = trimmedVersion(updated.officialLatestBuildVersion)
            ?? (updated.source?.kind == .mackedApp ? nil : trimmedVersion(updated.latestBuildVersion))
        let mackedVersion = trimmedVersion(updated.mackedLatestVersion)
            ?? (updated.source?.kind == .mackedApp ? trimmedVersion(updated.latestVersion) : nil)
        let mackedBuild = trimmedVersion(updated.mackedLatestBuildVersion)
            ?? (updated.source?.kind == .mackedApp ? trimmedVersion(updated.latestBuildVersion) : nil)

        let selectedVersion: String?
        let selectedBuild: String?
        let shouldRecalculateStatus: Bool
        switch (officialVersion, mackedVersion) {
        case let (.some(official), .some(macked)):
            switch VersionComparator.compare(
                current: official,
                latest: macked,
                currentBuild: officialBuild,
                latestBuild: mackedBuild
            ) {
            case .currentOlder:
                selectedVersion = macked
                selectedBuild = mackedBuild
                shouldRecalculateStatus = true
            case .equal, .currentNewer:
                if officialBuild == nil, mackedBuild != nil,
                   VersionComparator.compare(current: official, latest: macked) == .equal {
                    selectedVersion = macked
                    selectedBuild = mackedBuild
                } else {
                    selectedVersion = official
                    selectedBuild = officialBuild
                }
                shouldRecalculateStatus = trimmedVersion(updated.latestVersion) != selectedVersion
                    || trimmedVersion(updated.latestBuildVersion) != selectedBuild
                    || updated.source?.kind == .mackedApp
                    || updated.status == .unknown
                    || updated.status == .error
            case .unknown:
                return updated
            }
        case let (.some(official), .none):
            selectedVersion = official
            selectedBuild = officialBuild
            shouldRecalculateStatus = trimmedVersion(updated.latestVersion) != official
                || trimmedVersion(updated.latestBuildVersion) != officialBuild
                || updated.status == .unknown
                || updated.status == .error
        case let (.none, .some(macked)):
            selectedVersion = macked
            selectedBuild = mackedBuild
            shouldRecalculateStatus = true
        case (.none, .none):
            return updated
        }

        guard let selectedVersion else {
            return updated
        }

        updated.latestVersion = selectedVersion
        updated.latestBuildVersion = selectedBuild
        if shouldRecalculateStatus {
            updated.status = statusFor(
                current: app.shortVersion ?? updated.currentVersion,
                latest: selectedVersion,
                currentBuild: app.buildVersion,
                latestBuild: selectedBuild
            )
        }
        if updated.status == .updateAvailable || updated.status == .upToDate {
            updated.errorMessage = nil
        }
        return updated
    }

    private func statusFor(current: String?, latest: String?, currentBuild: String?, latestBuild: String?) -> UpdateStatus {
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

    private func trimmedVersion(_ version: String?) -> String? {
        let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
