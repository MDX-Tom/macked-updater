import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppLibraryViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var updateInfoByAppID: [String: AppUpdateInfo] = [:]
    @Published var userSources: [String: UserUpdateSource] = [:]
    @Published var settings: AppSettings = SettingsStore.load() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var selection: SidebarSelection = .allApps
    @Published var selectedAppID: String?
    @Published var searchText: String = ""
    @Published var isScanning = false
    @Published var isChecking = false
    @Published var statusMessage = "Ready"
    @Published var activeMackedDownloadAppIDs: Set<String> = []
    @Published var downloadQueue: [DownloadQueueItem] = []
    @Published var mackedLoginState = MackedLoginState(isLoggedIn: false, cookieCount: 0, summary: "Checking Macked.app session...")
    @Published var isShowingMackedLoginPrompt = false

    private let scanner = AppScanner()
    private let coordinator = UpdateCheckCoordinator()
    private let database = AppDatabase.shared
    private let sourceStore = UserSourceStore.shared
    private var didBootstrap = false

    var selectedApp: InstalledApp? {
        guard let selectedAppID else {
            return filteredApps.first ?? visibleApps.first
        }
        return visibleApps.first { $0.id == selectedAppID } ?? filteredApps.first ?? visibleApps.first
    }

    var visibleApps: [InstalledApp] {
        guard settings.excludeSystemApps else {
            return apps
        }
        return apps.filter { !$0.isSystemManagedApp }
    }

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return visibleApps.filter { app in
            let status = updateInfo(for: app).status
            let matchesSelection: Bool

            switch selection {
            case .allApps:
                matchesSelection = true
            case .updatesAvailable:
                matchesSelection = status == .updateAvailable
            case .upToDate:
                matchesSelection = status == .upToDate
            case .unknown:
                matchesSelection = status == .unknown || status == .error
            case .sources, .settings:
                matchesSelection = true
            }

            guard matchesSelection else {
                return false
            }

            guard !query.isEmpty else {
                return true
            }

            return app.name.lowercased().contains(query)
                || (app.bundleIdentifier?.lowercased().contains(query) ?? false)
                || app.installPath.lowercased().contains(query)
        }
    }

    func bootstrap() async {
        guard !didBootstrap else {
            return
        }
        didBootstrap = true

        updateInfoByAppID = await database.loadUpdateCache()
        userSources = await sourceStore.loadSources()
        await scanApps()
        await refreshMackedLoginState(promptIfMissing: settings.checkMackedApp)

        if settings.checkOnLaunch {
            await checkAllApps()
        }
    }

    func scanApps() async {
        isScanning = true
        statusMessage = "Scanning installed apps..."
        let scannedApps = await scanner.scanInstalledApps()
        apps = scannedApps
        await sanitizeCachedMackedMatches(for: scannedApps)
        await hydrateKnownMackedPagesInCache(for: scannedApps)
        if selectedAppID == nil || !visibleApps.contains(where: { $0.id == selectedAppID }) {
            selectedAppID = visibleApps.first?.id
        }
        isScanning = false
        if settings.excludeSystemApps {
            statusMessage = "Found \(scannedApps.count) apps, showing \(visibleApps.count) non-system apps"
        } else {
            statusMessage = "Found \(scannedApps.count) apps"
        }
    }

    func checkAllApps() async {
        guard !visibleApps.isEmpty else {
            return
        }

        isChecking = true
        defer { isChecking = false }
        statusMessage = "Step 1/2: checking official versions..."
        let appsToCheck = visibleApps
        let settingsSnapshot = settings
        let sourceSnapshot = userSources
        let coordinator = coordinator
        let cachedBeforeCheck = updateInfoByAppID
        let officialConcurrencyLimit = 12

        var checkingInfo = updateInfoByAppID
        for app in appsToCheck {
            checkingInfo[app.id] = .checking(for: app)
        }
        updateInfoByAppID = checkingInfo

        var officialCompleted = 0
        var pendingOfficialUpdates: [String: AppUpdateInfo] = [:]

        await withTaskGroup(of: (InstalledApp, AppUpdateInfo).self) { group in
            var iterator = appsToCheck.makeIterator()

            func addNext() {
                guard let app = iterator.next() else {
                    return
                }

                group.addTask {
                    let result = await coordinator.checkOfficial(
                        app: app,
                        userSource: sourceSnapshot[app.id],
                        settings: settingsSnapshot
                    )
                    return (app, result)
                }
            }

            for _ in 0..<min(officialConcurrencyLimit, appsToCheck.count) {
                addNext()
            }

            while let (app, info) = await group.next() {
                pendingOfficialUpdates[app.id] = preservingMackedMetadata(
                    in: info,
                    for: app,
                    previous: cachedBeforeCheck[app.id]
                )
                officialCompleted += 1
                if officialCompleted.isMultiple(of: 8) || officialCompleted == appsToCheck.count {
                    var published = updateInfoByAppID
                    published.merge(pendingOfficialUpdates) { _, new in new }
                    updateInfoByAppID = published
                    pendingOfficialUpdates.removeAll(keepingCapacity: true)
                    statusMessage = "Step 1/2: checked official versions for \(officialCompleted) of \(appsToCheck.count) apps"
                }
                addNext()
            }
        }

        guard settingsSnapshot.checkMackedApp else {
            statusMessage = "Official update check complete"
            await database.saveUpdateCache(updateInfoByAppID)
            return
        }

        guard await ensureMackedLogin(for: "Macked.app lookup") else {
            statusMessage = "Official check complete. Login to Macked.app to run step 2/2."
            await database.saveUpdateCache(updateInfoByAppID)
            return
        }

        statusMessage = "Step 2/2: checking Macked.app coverage..."
        let mackedConcurrencyLimit = 12
        var mackedCompleted = 0
        var pendingMackedUpdates: [String: AppUpdateInfo] = [:]

        await withTaskGroup(of: (InstalledApp, AppUpdateInfo?).self) { group in
            var iterator = appsToCheck.makeIterator()

            func addNext() {
                guard let app = iterator.next() else {
                    return
                }

                group.addTask {
                    let result = await coordinator.checkMacked(
                        app: app,
                        userSource: sourceSnapshot[app.id],
                        settings: settingsSnapshot,
                        cachedInfo: cachedBeforeCheck[app.id]
                    )
                    return (app, result)
                }
            }

            for _ in 0..<min(mackedConcurrencyLimit, appsToCheck.count) {
                addNext()
            }

            while let (app, mackedInfo) = await group.next() {
                let officialInfo = updateInfoByAppID[app.id]
                    ?? AppUpdateInfo.unknown(for: app, source: OfficialWebsiteResolver().unresolvedInfo(for: app).source)
                pendingMackedUpdates[app.id] = coordinator.merge(app: app, official: officialInfo, macked: mackedInfo)
                mackedCompleted += 1
                if mackedCompleted.isMultiple(of: 6) || mackedCompleted == appsToCheck.count {
                    var published = updateInfoByAppID
                    published.merge(pendingMackedUpdates) { _, new in new }
                    updateInfoByAppID = published
                    pendingMackedUpdates.removeAll(keepingCapacity: true)
                    statusMessage = "Step 2/2: checked Macked.app for \(mackedCompleted) of \(appsToCheck.count) apps"
                }
                addNext()
            }
        }

        await database.saveUpdateCache(updateInfoByAppID)
        statusMessage = "Two-step update check complete"
    }

    func checkSelectedApp() async {
        guard let app = selectedApp else {
            return
        }
        let previousInfo = updateInfoByAppID[app.id]
        updateInfoByAppID[app.id] = .checking(for: app)
        let official = await coordinator.checkOfficial(app: app, userSource: userSources[app.id], settings: settings)
        let officialWithMackedMetadata = preservingMackedMetadata(in: official, for: app, previous: previousInfo)
        updateInfoByAppID[app.id] = officialWithMackedMetadata

        if settings.checkMackedApp, await ensureMackedLogin(for: "Macked.app lookup") {
            statusMessage = "Checking \(app.name) on Macked.app..."
            let macked = await coordinator.checkMacked(
                app: app,
                userSource: userSources[app.id],
                settings: settings,
                cachedInfo: previousInfo
            )
            updateInfoByAppID[app.id] = coordinator.merge(app: app, official: officialWithMackedMetadata, macked: macked)
        }

        await database.saveUpdateCache(updateInfoByAppID)
        statusMessage = "Checked \(app.name)"
    }

    func updateInfo(for app: InstalledApp) -> AppUpdateInfo {
        let info = updateInfoByAppID[app.id]
            ?? AppUpdateInfo.unknown(for: app, source: OfficialWebsiteResolver().unresolvedInfo(for: app).source)
        return preservingMackedMetadata(in: info, for: app, previous: updateInfoByAppID[app.id])
    }

    func count(for selection: SidebarSelection) -> Int {
        switch selection {
        case .allApps:
            return visibleApps.count
        case .updatesAvailable:
            return visibleApps.filter { updateInfo(for: $0).status == .updateAvailable }.count
        case .upToDate:
            return visibleApps.filter { updateInfo(for: $0).status == .upToDate }.count
        case .unknown:
            return visibleApps.filter {
                let status = updateInfo(for: $0).status
                return status == .unknown || status == .error
            }.count
        case .sources:
            return userSources.count
        case .settings:
            return 0
        }
    }

    func saveUserSource(_ source: UserUpdateSource) async {
        var updated = source
        updated.updatedAt = Date()

        let validationMessages = SourceValidation.validationMessages(for: updated)
        guard validationMessages.isEmpty else {
            statusMessage = validationMessages.joined(separator: " ")
            return
        }

        if updated.hasAnySource {
            userSources[updated.appID] = updated
        } else {
            userSources.removeValue(forKey: updated.appID)
        }

        await sourceStore.save(updated)

        if let app = apps.first(where: { $0.id == updated.appID }) {
            let previousInfo = updateInfoByAppID[app.id]
            updateInfoByAppID[app.id] = .checking(for: app)
            let official = await coordinator.checkOfficial(app: app, userSource: userSources[app.id], settings: settings)
            let officialWithMackedMetadata = preservingMackedMetadata(in: official, for: app, previous: previousInfo)
            if settings.checkMackedApp, await ensureMackedLogin(for: "Macked.app lookup") {
                let macked = await coordinator.checkMacked(
                    app: app,
                    userSource: userSources[app.id],
                    settings: settings,
                    cachedInfo: previousInfo
                )
                updateInfoByAppID[app.id] = coordinator.merge(app: app, official: officialWithMackedMetadata, macked: macked)
            } else {
                updateInfoByAppID[app.id] = officialWithMackedMetadata
            }
            await database.saveUpdateCache(updateInfoByAppID)
        }
    }

    func removeUserSource(appID: String) async {
        userSources.removeValue(forKey: appID)
        await sourceStore.remove(appID: appID)
        if let app = apps.first(where: { $0.id == appID }) {
            updateInfoByAppID[app.id] = AppUpdateInfo.unknown(for: app, source: OfficialWebsiteResolver().unresolvedInfo(for: app).source)
            await database.saveUpdateCache(updateInfoByAppID)
        }
    }

    func clearCache() async {
        updateInfoByAppID = [:]
        await database.clearCache()
        statusMessage = "Cache cleared"
    }

    func refreshMackedLoginState(promptIfMissing: Bool = false) async {
        let state = await MackedCookieStore.loginState()
        mackedLoginState = state
        if settings.checkMackedApp, !state.isLoggedIn, promptIfMissing {
            statusMessage = "Login to Macked.app to enable Macked.app lookup and direct downloads"
            isShowingMackedLoginPrompt = true
        }
    }

    func promptForMackedLogin() {
        statusMessage = "Login to Macked.app to enable this feature"
        isShowingMackedLoginPrompt = true
    }

    @discardableResult
    func ensureMackedLogin(for feature: String) async -> Bool {
        await refreshMackedLoginState(promptIfMissing: false)
        guard mackedLoginState.isLoggedIn else {
            statusMessage = "Login to Macked.app to use \(feature)"
            isShowingMackedLoginPrompt = true
            return false
        }
        return true
    }

    func isDownloadingMackedUpdate(for app: InstalledApp) -> Bool {
        activeMackedDownloadAppIDs.contains(app.id)
    }

    func clearCompletedDownloads() {
        downloadQueue.removeAll { $0.status == .completed || $0.status == .failed }
    }

    func downloadMackedUpdate(for app: InstalledApp, info: AppUpdateInfo) async {
        guard await ensureMackedLogin(for: "Macked.app download") else {
            return
        }

        var mutableInfo = info
        var downloadURL = mutableInfo.mackedDownloadURL

        @discardableResult
        func refreshMackedDownloadLink(reason: String) async -> URL? {
            guard let pageURL = mutableInfo.mackedPageURL else {
                return nil
            }
            statusMessage = "Refreshing Macked.app download link for \(app.name)..."
            do {
                let detail = try await MackedAppChecker().freshDetail(pageURL: pageURL)
                let refreshedURL = detail.downloadURL
                mutableInfo.mackedDownloadURL = detail.downloadURL
                mutableInfo.downloadURL = mutableInfo.officialDownloadURL ?? mutableInfo.downloadURL
                mutableInfo.mackedLatestVersion = detail.latestVersion ?? mutableInfo.mackedLatestVersion
                mutableInfo.mackedLatestBuildVersion = detail.latestBuildVersion ?? mutableInfo.mackedLatestBuildVersion
                mutableInfo.mackedPageURL = detail.pageURL
                mutableInfo.mackedLoginURL = detail.loginURL
                mutableInfo.loginURL = detail.loginURL
                mutableInfo.mackedSourceName = UpdateSourceKind.mackedApp.title
                updateInfoByAppID[app.id] = mutableInfo
                await database.saveUpdateCache(updateInfoByAppID)
                if refreshedURL != nil {
                    statusMessage = "Macked.app download link refreshed for \(app.name)"
                } else {
                    statusMessage = "Macked.app page refreshed, but no direct download link was found for \(app.name)"
                }
                return refreshedURL
            } catch {
                statusMessage = "Macked.app download link refresh failed\(reason.isEmpty ? "" : " after \(reason)"): \(error.localizedDescription)"
                return nil
            }
        }

        if downloadURL == nil || MackedDownloadManager.isWebAssetURL(downloadURL) {
            downloadURL = await refreshMackedDownloadLink(reason: "missing cached link")
        }

        guard let downloadURL else {
            statusMessage = "No Macked.app download link for \(app.name)"
            return
        }

        guard !MackedDownloadManager.isWebAssetURL(downloadURL) else {
            statusMessage = "Macked.app returned a web asset instead of a download for \(app.name). Refresh the app and try again."
            return
        }

        let queueID = UUID()
        downloadQueue.insert(
            DownloadQueueItem(
                id: queueID,
                appID: app.id,
                appName: app.name,
                sourceURL: downloadURL,
                status: .queued,
                bytesWritten: 0,
                totalBytesExpected: nil,
                bytesPerSecond: nil,
                fileURL: nil,
                errorMessage: nil,
                startedAt: Date(),
                completedAt: nil
            ),
            at: 0
        )
        activeMackedDownloadAppIDs.insert(app.id)
        statusMessage = "Downloading \(app.name) from Macked.app..."
        updateDownloadQueueItem(queueID) { item in
            item.status = .downloading
        }
        defer {
            activeMackedDownloadAppIDs.remove(app.id)
        }

        do {
            var activeDownloadURL = downloadURL
            updateDownloadQueueItem(queueID) { item in
                item.sourceURL = activeDownloadURL
            }
            var result: MackedDownloadResult
            do {
                result = try await performMackedDownload(
                    from: activeDownloadURL,
                    app: app,
                    info: mutableInfo,
                    queueID: queueID
                )
            } catch {
                guard shouldRefreshMackedDownloadLink(after: error),
                      let refreshedURL = await refreshMackedDownloadLink(reason: "download failure"),
                      refreshedURL != activeDownloadURL
                else {
                    throw error
                }

                activeDownloadURL = refreshedURL
                updateDownloadQueueItem(queueID) { item in
                    item.status = .downloading
                    item.sourceURL = activeDownloadURL
                    item.bytesWritten = 0
                    item.totalBytesExpected = nil
                    item.bytesPerSecond = nil
                    item.errorMessage = nil
                }
                result = try await performMackedDownload(
                    from: activeDownloadURL,
                    app: app,
                    info: mutableInfo,
                    queueID: queueID
                )
            }
            updateDownloadQueueItem(queueID) { item in
                item.status = .completed
                item.fileURL = result.fileURL
                item.bytesWritten = result.byteCount ?? item.bytesWritten
                item.totalBytesExpected = item.totalBytesExpected ?? result.byteCount
                item.bytesPerSecond = nil
                item.completedAt = Date()
            }
            statusMessage = "Downloaded \(result.fileURL.lastPathComponent) to Downloads"
            NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
        } catch {
            updateDownloadQueueItem(queueID) { item in
                item.status = .failed
                item.errorMessage = error.localizedDescription
                item.bytesPerSecond = nil
                item.completedAt = Date()
            }
            statusMessage = "Macked.app download failed: \(error.localizedDescription)"
        }
    }

    private func performMackedDownload(
        from downloadURL: URL,
        app: InstalledApp,
        info: AppUpdateInfo,
        queueID: UUID
    ) async throws -> MackedDownloadResult {
        try await MackedDownloadManager.download(
            from: downloadURL,
            suggestedBaseName: app.name,
            refererURL: info.mackedPageURL,
            progress: { [weak self] written, expected, speed in
                await MainActor.run {
                    self?.updateDownloadQueueItem(queueID) { item in
                        item.status = .downloading
                        item.bytesWritten = written
                        item.totalBytesExpected = expected
                        item.bytesPerSecond = speed
                    }
                }
            }
        )
    }

    private func shouldRefreshMackedDownloadLink(after error: Error) -> Bool {
        if let downloadError = error as? MackedDownloadError {
            switch downloadError {
            case .invalidHTTPStatus, .htmlResponse, .nonDownloadResponse, .redirectLoop:
                return true
            case .downloadsDirectoryUnavailable, .emptyDownloadedFile:
                return false
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    private func updateDownloadQueueItem(_ id: UUID, mutate: (inout DownloadQueueItem) -> Void) {
        guard let index = downloadQueue.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&downloadQueue[index])
    }

    private func hydrateKnownMackedPagesInCache(for scannedApps: [InstalledApp]) async {
        var didChange = false

        for app in scannedApps {
            guard let knownPageURL = MackedAppChecker.knownMackedPageURL(for: app) else {
                continue
            }

            let previous = updateInfoByAppID[app.id]
            var info = previous ?? AppUpdateInfo.unknown(
                for: app,
                source: OfficialWebsiteResolver().unresolvedInfo(for: app).source
            )

            let alreadyHasMacked = info.mackedPageURL != nil
                || info.mackedLatestVersion != nil
                || info.mackedLatestBuildVersion != nil
                || info.mackedSourceName != nil
            guard !alreadyHasMacked || info.errorMessage?.localizedCaseInsensitiveContains("No Macked.app result") == true else {
                continue
            }

            info.mackedPageURL = knownPageURL
            info.mackedLoginURL = MackedAppChecker.makeLoginURL(redirectingTo: knownPageURL)
            info.mackedSourceName = UpdateSourceKind.mackedApp.title
            info.releaseNotesURL = info.releaseNotesURL ?? knownPageURL
            info.downloadURL = info.officialDownloadURL ?? info.mackedDownloadURL ?? info.downloadURL
            info.errorMessage = nil
            updateInfoByAppID[app.id] = info
            didChange = true
        }

        if didChange {
            await database.saveUpdateCache(updateInfoByAppID)
        }
    }

    private func sanitizeCachedMackedMatches(for scannedApps: [InstalledApp]) async {
        var didChange = false
        let resolver = OfficialWebsiteResolver()

        for app in scannedApps where MackedAppChecker.shouldSkipMackedLookup(for: app) {
            guard var info = updateInfoByAppID[app.id] else {
                continue
            }

            let hadMackedMetadata = info.mackedPageURL != nil
                || info.mackedDownloadURL != nil
                || info.mackedLatestVersion != nil
                || info.mackedLatestBuildVersion != nil
                || info.mackedSourceName != nil
                || info.source?.kind == .mackedApp

            guard hadMackedMetadata else {
                continue
            }

            info.mackedPageURL = nil
            info.mackedDownloadURL = nil
            info.mackedLoginURL = nil
            info.mackedSourceName = nil
            info.mackedLatestVersion = nil
            info.mackedLatestBuildVersion = nil
            info.loginURL = nil
            info.downloadURL = info.officialDownloadURL

            if info.source?.kind == .mackedApp {
                if let officialLatestVersion = info.officialLatestVersion {
                    info.latestVersion = officialLatestVersion
                    info.latestBuildVersion = info.officialLatestBuildVersion
                    info.source = UpdateSource(
                        kind: .officialWebsite,
                        name: info.officialSourceName ?? "Official",
                        identifier: info.officialPageURL?.absoluteString,
                        pageURL: info.officialPageURL,
                        feedURL: nil
                    )
                } else {
                    let fallback = resolver.unresolvedInfo(for: app)
                    info.latestVersion = nil
                    info.latestBuildVersion = nil
                    info.status = .unknown
                    info.source = fallback.source
                    info.officialPageURL = fallback.officialPageURL
                    info.officialDownloadURL = nil
                    info.officialSourceName = nil
                    info.officialIsFree = nil
                    info.downloadURL = nil
                    info.releaseNotesURL = nil
                }
            }

            info.errorMessage = nil
            updateInfoByAppID[app.id] = info
            didChange = true
        }

        if didChange {
            await database.saveUpdateCache(updateInfoByAppID)
        }
    }

    private func preservingMackedMetadata(
        in info: AppUpdateInfo,
        for app: InstalledApp,
        previous: AppUpdateInfo?
    ) -> AppUpdateInfo {
        var enriched = info

        if enriched.mackedPageURL == nil {
            enriched.mackedPageURL = previous?.mackedPageURL ?? MackedAppChecker.knownMackedPageURL(for: app)
        }
        if enriched.mackedDownloadURL == nil {
            enriched.mackedDownloadURL = previous?.mackedDownloadURL
        }
        if enriched.mackedLatestVersion == nil {
            enriched.mackedLatestVersion = previous?.mackedLatestVersion
        }
        if enriched.mackedLatestBuildVersion == nil {
            enriched.mackedLatestBuildVersion = previous?.mackedLatestBuildVersion
        }
        if enriched.mackedSourceName == nil,
           enriched.mackedPageURL != nil
            || enriched.mackedDownloadURL != nil
            || enriched.mackedLatestVersion != nil
            || enriched.mackedLatestBuildVersion != nil {
            enriched.mackedSourceName = previous?.mackedSourceName ?? UpdateSourceKind.mackedApp.title
        }
        if enriched.mackedLoginURL == nil, let pageURL = enriched.mackedPageURL {
            enriched.mackedLoginURL = previous?.mackedLoginURL ?? MackedAppChecker.makeLoginURL(redirectingTo: pageURL)
        }
        if enriched.loginURL == nil {
            enriched.loginURL = enriched.mackedLoginURL ?? previous?.loginURL
        }
        if enriched.downloadURL == nil {
            enriched.downloadURL = enriched.officialDownloadURL ?? enriched.mackedDownloadURL ?? previous?.downloadURL
        }

        return coordinator.merge(app: app, official: enriched, macked: nil)
    }
}
