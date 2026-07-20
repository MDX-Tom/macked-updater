import XCTest
@testable import MackedUpdater

final class UpdateCheckCoordinatorValidationTests: XCTestCase {
    func testCoordinatorIgnoresMalformedStoredSourceAndFallsBack() async {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let source = UserUpdateSource(
            appID: app.id,
            appName: app.name,
            officialPageURLString: "fixture",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        let result = await UpdateCheckCoordinator().check(
            app: app,
            userSource: source,
            settings: AppSettings(autoScanIntervalHours: 24, checkOnLaunch: false, checkHomebrewCask: false, checkSparkleAppcast: false, checkMackedApp: false, excludeSystemApps: true)
        )

        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.source?.kind, .manualSearch)
        XCTAssertNotNil(result.officialPageURL)
        XCTAssertNil(result.downloadURL)
        XCTAssertNil(result.releaseNotesURL)
        XCTAssertNil(result.errorMessage)
    }

    func testMergeUsesMackedVersionWhenItIsNewerThanOfficialAndAddsMackedMetadata() {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let official = AppUpdateInfo(
            appID: app.id,
            currentVersion: "1.0.0",
            latestVersion: "1.0.0",
            status: .upToDate,
            source: UpdateSource(kind: .sparkleAppcast, name: "Sparkle", identifier: nil, pageURL: URL(string: "https://example.com"), feedURL: nil),
            officialPageURL: URL(string: "https://example.com"),
            downloadURL: URL(string: "https://example.com/download"),
            releaseNotesURL: URL(string: "https://example.com/notes"),
            lastCheckedAt: Date(),
            errorMessage: nil
        )
        let macked = AppUpdateInfo(
            appID: app.id,
            currentVersion: "1.0.0",
            latestVersion: "2.0.0",
            status: .updateAvailable,
            source: UpdateSource(kind: .mackedApp, name: "Macked.app", identifier: nil, pageURL: URL(string: "https://macked.app/fixture.html"), feedURL: nil),
            officialPageURL: nil,
            downloadURL: URL(string: "https://macked.app/download"),
            releaseNotesURL: URL(string: "https://macked.app/fixture.html"),
            mackedPageURL: URL(string: "https://macked.app/fixture.html"),
            mackedDownloadURL: URL(string: "https://macked.app/download"),
            mackedSourceName: "Macked.app",
            mackedLatestVersion: "2.0.0",
            lastCheckedAt: Date(),
            errorMessage: nil
        )

        let merged = UpdateCheckCoordinator().merge(app: app, official: official, macked: macked)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "2.0.0")
        XCTAssertEqual(merged.officialLatestVersion, "1.0.0")
        XCTAssertEqual(merged.mackedLatestVersion, "2.0.0")
        XCTAssertEqual(merged.mackedDownloadURL?.absoluteString, "https://macked.app/download")
    }

    func testMergeUsesMackedVersionWhenOfficialVersionLooksOlderThanInstalled() {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "12.0",
            buildVersion: "1200",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let official = AppUpdateInfo(
            appID: app.id,
            currentVersion: "12.0",
            latestVersion: "3.3",
            status: .upToDate,
            source: UpdateSource(kind: .officialWebsite, name: "Official", identifier: nil, pageURL: URL(string: "https://example.com"), feedURL: nil),
            officialPageURL: URL(string: "https://example.com"),
            downloadURL: URL(string: "https://example.com/download"),
            releaseNotesURL: URL(string: "https://example.com/notes"),
            lastCheckedAt: Date(),
            errorMessage: nil
        )
        let macked = AppUpdateInfo(
            appID: app.id,
            currentVersion: "12.0",
            latestVersion: "12.3",
            status: .updateAvailable,
            source: UpdateSource(kind: .mackedApp, name: "Macked.app", identifier: nil, pageURL: URL(string: "https://macked.app/fixture.html"), feedURL: nil),
            officialPageURL: nil,
            downloadURL: URL(string: "https://macked.app/download"),
            releaseNotesURL: URL(string: "https://macked.app/fixture.html"),
            mackedPageURL: URL(string: "https://macked.app/fixture.html"),
            mackedDownloadURL: URL(string: "https://macked.app/download"),
            mackedSourceName: "Macked.app",
            mackedLatestVersion: "12.3",
            lastCheckedAt: Date(),
            errorMessage: nil
        )

        let merged = UpdateCheckCoordinator().merge(app: app, official: official, macked: macked)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "12.3")
        XCTAssertEqual(merged.officialLatestVersion, "3.3")
        XCTAssertEqual(merged.mackedLatestVersion, "12.3")
        XCTAssertEqual(merged.mackedPageURL?.absoluteString, "https://macked.app/fixture.html")
    }

    func testMergeUsesOfficialVersionWhenItIsNewerThanMackedVersion() {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "12.0",
            buildVersion: "1200",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let official = AppUpdateInfo(
            appID: app.id,
            currentVersion: "12.0",
            latestVersion: "13.0",
            status: .updateAvailable,
            source: UpdateSource(kind: .sparkleAppcast, name: "Sparkle", identifier: nil, pageURL: URL(string: "https://example.com"), feedURL: nil),
            officialPageURL: URL(string: "https://example.com"),
            downloadURL: URL(string: "https://example.com/download"),
            releaseNotesURL: URL(string: "https://example.com/notes"),
            lastCheckedAt: Date(),
            errorMessage: nil
        )
        let macked = AppUpdateInfo(
            appID: app.id,
            currentVersion: "12.0",
            latestVersion: "12.3",
            status: .updateAvailable,
            source: UpdateSource(kind: .mackedApp, name: "Macked.app", identifier: nil, pageURL: URL(string: "https://macked.app/fixture.html"), feedURL: nil),
            officialPageURL: nil,
            downloadURL: URL(string: "https://macked.app/download"),
            releaseNotesURL: URL(string: "https://macked.app/fixture.html"),
            mackedPageURL: URL(string: "https://macked.app/fixture.html"),
            mackedDownloadURL: URL(string: "https://macked.app/download"),
            mackedSourceName: "Macked.app",
            mackedLatestVersion: "12.3",
            lastCheckedAt: Date(),
            errorMessage: nil
        )

        let merged = UpdateCheckCoordinator().merge(app: app, official: official, macked: macked)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "13.0")
        XCTAssertEqual(merged.officialLatestVersion, "13.0")
        XCTAssertEqual(merged.mackedLatestVersion, "12.3")
        XCTAssertEqual(merged.mackedDownloadURL?.absoluteString, "https://macked.app/download")
    }

    func testMergeUsesMackedAsOfficialFallbackWhenOfficialVersionIsUnknown() {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let official = OfficialWebsiteResolver().unresolvedInfo(for: app)
        let macked = AppUpdateInfo(
            appID: app.id,
            currentVersion: "1.0.0",
            latestVersion: "2.0.0",
            status: .updateAvailable,
            source: UpdateSource(kind: .mackedApp, name: "Macked.app", identifier: nil, pageURL: URL(string: "https://macked.app/fixture.html"), feedURL: nil),
            officialPageURL: nil,
            downloadURL: URL(string: "https://macked.app/download"),
            releaseNotesURL: URL(string: "https://macked.app/fixture.html"),
            mackedPageURL: URL(string: "https://macked.app/fixture.html"),
            mackedDownloadURL: URL(string: "https://macked.app/download"),
            mackedSourceName: "Macked.app",
            mackedLatestVersion: "2.0.0",
            lastCheckedAt: Date(),
            errorMessage: nil
        )

        let merged = UpdateCheckCoordinator().merge(app: app, official: official, macked: macked)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "2.0.0")
        XCTAssertEqual(merged.officialLatestVersion, "2.0.0")
        XCTAssertEqual(merged.officialSourceName, "Macked.app")
        XCTAssertEqual(merged.source?.kind, .mackedApp)
    }

    func testCachedMackedMetadataCanDriveLatestWithoutBecomingOfficialDownload() {
        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        var cached = OfficialWebsiteResolver().unresolvedInfo(for: app)
        cached.mackedLatestVersion = "2.0.0"
        cached.mackedPageURL = URL(string: "https://macked.app/fixture.html")
        cached.mackedDownloadURL = URL(string: "https://macked.app/download")
        cached.mackedSourceName = "Macked.app"
        cached.downloadURL = cached.mackedDownloadURL

        let merged = UpdateCheckCoordinator().merge(app: app, official: cached, macked: nil)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "2.0.0")
        XCTAssertEqual(merged.mackedLatestVersion, "2.0.0")
        XCTAssertEqual(merged.mackedDownloadURL?.absoluteString, "https://macked.app/download")
        XCTAssertNil(merged.officialDownloadURL)
    }

    func testMergeUsesNewerDetailedBuildWhenShortVersionsMatch() {
        let app = InstalledApp(
            name: "iMazing",
            bundleIdentifier: "com.DigiDNA.iMazing3Mac",
            shortVersion: "3.5.5",
            buildVersion: "24057",
            installPath: "/Applications/iMazing.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let official = AppUpdateInfo(
            appID: app.id,
            currentVersion: "3.5.5",
            latestVersion: "3.5.5",
            latestBuildVersion: "24057",
            status: .upToDate,
            source: UpdateSource(kind: .sparkleAppcast, name: "Sparkle", identifier: nil, pageURL: nil, feedURL: nil),
            officialPageURL: nil,
            downloadURL: nil,
            releaseNotesURL: nil,
            lastCheckedAt: Date(),
            errorMessage: nil
        )
        let macked = AppUpdateInfo(
            appID: app.id,
            currentVersion: "3.5.5",
            latestVersion: "3.5.5",
            latestBuildVersion: "24058",
            status: .updateAvailable,
            source: UpdateSource(
                kind: .mackedApp,
                name: "Macked.app",
                identifier: nil,
                pageURL: URL(string: "https://macked.app/imazing-3-crack.html"),
                feedURL: nil
            ),
            officialPageURL: nil,
            downloadURL: nil,
            releaseNotesURL: nil,
            mackedPageURL: URL(string: "https://macked.app/imazing-3-crack.html"),
            mackedSourceName: "Macked.app",
            mackedLatestVersion: "3.5.5",
            mackedLatestBuildVersion: "24058",
            lastCheckedAt: Date(),
            errorMessage: nil
        )

        let merged = UpdateCheckCoordinator().merge(app: app, official: official, macked: macked)

        XCTAssertEqual(merged.status, .updateAvailable)
        XCTAssertEqual(merged.latestVersion, "3.5.5")
        XCTAssertEqual(merged.latestBuildVersion, "24058")
        XCTAssertEqual(merged.latestDisplayVersion, "3.5.5 (24058)")
    }
}
