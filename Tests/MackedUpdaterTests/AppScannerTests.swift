import AppKit
import XCTest
@testable import MackedUpdater

final class AppScannerTests: XCTestCase {
    func testScansApplicationsWithReadableMetadataAndIcon() async throws {
        let apps = await AppScanner().scanInstalledApps()

        XCTAssertFalse(apps.isEmpty)
        XCTAssertTrue(apps.contains { $0.installPath.hasPrefix("/Applications/") })

        let app = try XCTUnwrap(apps.first { $0.installPath.hasPrefix("/Applications/") })
        XCTAssertFalse(app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(app.installPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let icon = NSWorkspace.shared.icon(forFile: app.installPath)
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertGreaterThan(icon.size.height, 0)

        if let finalCutCreatorStudio = apps.first(where: { $0.installPath == "/Applications/Final Cut Pro Creator Studio.app" }) {
            XCTAssertFalse(finalCutCreatorStudio.isSystemManagedApp)
            XCTAssertTrue(finalCutCreatorStudio.hasMacAppStoreReceipt)
        }

        if let adobeActivationTool = apps.first(where: { $0.installPath == "/Applications/Adobe Activation Tool.app" }) {
            XCTAssertFalse(adobeActivationTool.isSystemManagedApp)
            XCTAssertEqual(
                MackedAppChecker.knownMackedPageURL(for: adobeActivationTool)?.absoluteString,
                "https://macked.app/adobe-activation-tool-crack.html"
            )
        }
    }
}
