import XCTest
@testable import MackedUpdater

final class AdobeOfficialCheckerTests: XCTestCase {
    func testMatchesInstalledAdobeProductsButNotActivationTool() {
        let photoshop = InstalledApp(
            name: "Adobe Photoshop 2026",
            bundleIdentifier: "com.adobe.Photoshop",
            shortVersion: "27.7.0",
            buildVersion: "27.7.0",
            installPath: "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )
        let activationTool = InstalledApp(
            name: "Adobe Activation Tool",
            bundleIdentifier: "app.macked.Adobe-Activation-Tool",
            shortVersion: "1.2.7",
            buildVersion: "0",
            installPath: "/Applications/Adobe Activation Tool.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )

        XCTAssertEqual(AdobeProduct.match(app: photoshop)?.id, "photoshop")
        XCTAssertNil(AdobeProduct.match(app: activationTool))
    }

    func testParsesAdobeLatestVersionFromReleaseNotesText() {
        let html = #"""
        <html><body>
          <h2>June 2026 release (version 27.8)</h2>
          <p>The latest and most current version of Adobe Photoshop is 27.8.</p>
        </body></html>
        """#

        let version = AdobeOfficialChecker.extractLatestVersion(
            from: html,
            product: AdobeProduct.products.first { $0.id == "photoshop" }!
        )

        XCTAssertEqual(version, "27.8")
    }
}
