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
        XCTAssertEqual(info.latestBuildVersion, "200")
        XCTAssertEqual(info.latestDisplayVersion, "2.0.0 (200)")
        XCTAssertEqual(info.downloadURL?.absoluteString, "https://example.com/download/Macked.zip")
        XCTAssertEqual(info.releaseNotesURL?.absoluteString, "https://example.com/releases/2.0.0")
    }

    func testLocalAppcastDetectsNewerBuildWithinSameShortVersion() async throws {
        let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item>
            <title>Version 3.5.5</title>
            <enclosure url="https://example.com/iMazing.zip" sparkle:shortVersionString="3.5.5" sparkle:version="24058" />
          </item></channel>
        </rss>
        """
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")
        try appcast.data(using: .utf8)?.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let app = InstalledApp(
            name: "iMazing",
            bundleIdentifier: "com.DigiDNA.iMazing3Mac",
            shortVersion: "3.5.5",
            buildVersion: "24057",
            installPath: "/Applications/iMazing.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: temporaryURL,
            hasMacAppStoreReceipt: false,
            scanPriority: 2
        )

        let info = await SparkleAppcastChecker().check(app: app, feedURL: temporaryURL)

        XCTAssertEqual(info.status, .updateAvailable)
        XCTAssertEqual(info.latestVersion, "3.5.5")
        XCTAssertEqual(info.latestBuildVersion, "24058")
        XCTAssertEqual(info.latestDisplayVersion, "3.5.5 (24058)")
    }
}
