import XCTest
@testable import MackedUpdater

final class SparkleAppcastCheckerTests: XCTestCase {
    func testLocalAppcastDetectsNewerVersion() async throws {
        let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 2.0.0</title>
              <sparkle:releaseNotesLink>https://example.com/releases/2.0.0</sparkle:releaseNotesLink>
              <enclosure
                url="https://example.com/download/Macked.zip"
                sparkle:shortVersionString="2.0.0"
                sparkle:version="200" />
            </item>
          </channel>
        </rss>
        """

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")
        try appcast.data(using: .utf8)?.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let app = InstalledApp(
            name: "Fixture App",
            bundleIdentifier: "com.example.fixture",
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: "/Applications/Fixture.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: temporaryURL,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )

        let info = await SparkleAppcastChecker().check(app: app, feedURL: temporaryURL)

        XCTAssertEqual(info.status, .updateAvailable)
        XCTAssertEqual(info.latestVersion, "2.0.0")
        XCTAssertEqual(info.downloadURL?.absoluteString, "https://example.com/download/Macked.zip")
        XCTAssertEqual(info.releaseNotesURL?.absoluteString, "https://example.com/releases/2.0.0")
    }
}
