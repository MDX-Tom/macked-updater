import XCTest
@testable import MackedUpdater

final class SourceValidationTests: XCTestCase {
    func testAllowsUserConfiguredWebsiteSource() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            officialPageURLString: "https://example.com/apps/fixture",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        XCTAssertEqual(SourceValidation.validationMessages(for: source), [])
        XCTAssertTrue(SourceValidation.isAllowed(source))
    }

    func testAllowsOfficialAndGitHubSources() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            officialPageURLString: "https://example.com/apps/fixture",
            appcastURLString: "https://example.com/apps/fixture/appcast.xml",
            githubReleasesURLString: "https://github.com/example/fixture/releases",
            homebrewCaskName: "fixture",
            updatedAt: Date()
        )

        XCTAssertEqual(SourceValidation.validationMessages(for: source), [])
        XCTAssertTrue(SourceValidation.isAllowed(source))
    }

    func testReportsGitHubReleaseFieldForNonGitHubHost() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "https://example.com/releases",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        XCTAssertFalse(SourceValidation.validationMessages(for: source).isEmpty)
    }

    func testAllowsLocalAuthorizedCatalogURL() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            authorizedCatalogURLString: "file:///tmp/authorized-catalog.json",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        XCTAssertEqual(SourceValidation.validationMessages(for: source), [])
    }

    func testAllowsConfiguredCatalogHost() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            authorizedCatalogURLString: "https://catalog.example.com/catalog.json",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        XCTAssertEqual(SourceValidation.validationMessages(for: source), [])
    }


    func testAllowsMackedPageSource() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            mackedAppURLString: "https://macked.app/vibeproxy-ai-mac.html",
            mackedSearchQuery: "Fixture",
            updatedAt: Date()
        )

        XCTAssertEqual(SourceValidation.validationMessages(for: source), [])
    }

    func testReportsUnsupportedCatalogScheme() {
        let source = UserUpdateSource(
            appID: "com.example.fixture",
            appName: "Fixture",
            authorizedCatalogURLString: "ftp://catalog.example.com/catalog.json",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            updatedAt: Date()
        )

        XCTAssertFalse(SourceValidation.validationMessages(for: source).isEmpty)
    }
}
