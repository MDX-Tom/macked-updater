import XCTest
@testable import MackedUpdater

final class AuthorizedUpdateCatalogCheckerTests: XCTestCase {
    func testLocalCatalogDetectsNewerAuthorizedVersion() async throws {
        let catalogURL = try writeCatalog(
            """
            {
              "schemaVersion": 1,
              "sourceName": "Example Authorized Catalog",
              "apps": [
                {
                  "bundleIdentifier": "com.example.fixture",
                  "name": "Fixture App",
                  "latestVersion": "2.0.0",
                  "buildVersion": "200",
                  "officialPageURL": "https://example.com/apps/fixture",
                  "releaseNotesURL": "https://example.com/apps/fixture/releases/2.0.0",
                  "downloadURL": "https://example.com/apps/fixture/download"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        let result = await AuthorizedUpdateCatalogChecker().check(app: fixtureApp, catalogURL: catalogURL)

        XCTAssertEqual(result.status, .updateAvailable)
        XCTAssertEqual(result.latestVersion, "2.0.0")
        XCTAssertEqual(result.source?.kind, .authorizedCatalog)
        XCTAssertEqual(result.source?.name, "Example Authorized Catalog")
        XCTAssertEqual(result.officialPageURL?.absoluteString, "https://example.com/apps/fixture")
        XCTAssertEqual(result.releaseNotesURL?.absoluteString, "https://example.com/apps/fixture/releases/2.0.0")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://example.com/apps/fixture/download")
    }

    func testCatalogEntryReportsUnsupportedDownloadScheme() async throws {
        let catalogURL = try writeCatalog(
            """
            {
              "sourceName": "Fixture Catalog",
              "apps": [
                {
                  "bundleIdentifier": "com.example.fixture",
                  "latestVersion": "2.0.0",
                  "downloadURL": "ftp://example.com/fixture"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        let result = await AuthorizedUpdateCatalogChecker().check(app: fixtureApp, catalogURL: catalogURL)

        XCTAssertEqual(result.status, .error)
        XCTAssertNil(result.downloadURL)
        XCTAssertTrue(result.errorMessage?.contains("must use http or https") == true)
    }

    func testCatalogSupportsAuthenticatedDownloadPageURL() async throws {
        let catalogURL = try writeCatalog(
            """
            {
              "sourceName": "Authenticated Catalog",
              "apps": [
                {
                  "bundleIdentifier": "com.example.fixture",
                  "latestVersion": "2.0.0",
                  "downloadPageURL": "https://example.com/account/downloads/fixture"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        let result = await AuthorizedUpdateCatalogChecker().check(app: fixtureApp, catalogURL: catalogURL)

        XCTAssertEqual(result.status, .updateAvailable)
        XCTAssertEqual(result.source?.kind, .authorizedCatalog)
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://example.com/account/downloads/fixture")
    }

    func testCatalogSearchFindsAppLinksAndAuthenticatedDownloadPage() async throws {
        let catalogURL = try writeCatalog(
            """
            {
              "sourceName": "Searchable Catalog",
              "apps": [
                {
                  "bundleIdentifier": "com.example.fixture",
                  "appID": "fixture",
                  "name": "Fixture App",
                  "latestVersion": "2.0.0",
                  "officialPageURL": "https://example.com/apps/fixture",
                  "releaseNotesURL": "https://example.com/apps/fixture/releases",
                  "downloadPageURL": "https://example.com/account/downloads/fixture"
                },
                {
                  "bundleIdentifier": "com.example.other",
                  "name": "Other App",
                  "latestVersion": "1.0.0"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        let results = try await AuthorizedUpdateCatalogChecker().search(catalogURL: catalogURL, query: "fixture")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Fixture App")
        XCTAssertEqual(results.first?.bundleIdentifier, "com.example.fixture")
        XCTAssertEqual(results.first?.latestVersion, "2.0.0")
        XCTAssertEqual(results.first?.officialPageURL?.absoluteString, "https://example.com/apps/fixture")
        XCTAssertEqual(results.first?.releaseNotesURL?.absoluteString, "https://example.com/apps/fixture/releases")
        XCTAssertEqual(results.first?.downloadURL?.absoluteString, "https://example.com/account/downloads/fixture")
    }

    func testCoordinatorUsesAuthorizedCatalogBeforeFallbackSources() async throws {
        let catalogURL = try writeCatalog(
            """
            {
              "sourceName": "Coordinator Catalog",
              "apps": [
                {
                  "bundleIdentifier": "com.example.fixture",
                  "latestVersion": "2.0.0",
                  "officialPageURL": "https://example.com/apps/fixture"
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        let source = UserUpdateSource(
            appID: fixtureApp.id,
            appName: fixtureApp.name,
            authorizedCatalogURLString: catalogURL.absoluteString,
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        let result = await UpdateCheckCoordinator().check(
            app: fixtureApp,
            userSource: source,
            settings: AppSettings(autoScanIntervalHours: 24, checkOnLaunch: false, checkHomebrewCask: false, checkSparkleAppcast: true, checkMackedApp: false, excludeSystemApps: true)
        )

        XCTAssertEqual(result.status, .updateAvailable)
        XCTAssertEqual(result.source?.kind, .authorizedCatalog)
        XCTAssertEqual(result.source?.name, "Coordinator Catalog")
        XCTAssertEqual(result.latestVersion, "2.0.0")
    }

    private var fixtureApp: InstalledApp {
        InstalledApp(
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
    }

    private func writeCatalog(_ catalog: String) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try catalog.data(using: .utf8)?.write(to: temporaryURL)
        return temporaryURL
    }
}
