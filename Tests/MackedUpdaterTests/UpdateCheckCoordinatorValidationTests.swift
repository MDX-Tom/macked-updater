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

    func testMergeKeepsOfficialStatusWhenOfficialVersionExistsAndAddsMackedMetadata() {
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

        XCTAssertEqual(merged.status, .upToDate)
        XCTAssertEqual(merged.latestVersion, "1.0.0")
        XCTAssertEqual(merged.officialLatestVersion, "1.0.0")
        XCTAssertEqual(merged.mackedLatestVersion, "2.0.0")
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
}
