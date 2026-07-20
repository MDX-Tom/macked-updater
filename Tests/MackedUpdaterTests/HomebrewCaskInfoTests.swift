import XCTest
@testable import MackedUpdater

final class HomebrewCaskInfoTests: XCTestCase {
    func testParsesFlexibleCaskMetadata() throws {
        let json: [String: Any] = [
            "token": "fixture-app",
            "name": ["Fixture App"],
            "version": "2.4.1,200",
            "homepage": "https://example.com",
            "artifacts": [
                ["app": ["Fixture App.app"]],
                ["app": [["Fixture Helper.app", ["target": "Fixture.app"]]]]
            ]
        ]

        let info = try XCTUnwrap(HomebrewCaskInfo(json: json))

        XCTAssertEqual(info.token, "fixture-app")
        XCTAssertEqual(info.names, ["Fixture App"])
        XCTAssertEqual(info.version, "2.4.1,200")
        XCTAssertEqual(info.comparableVersion, "2.4.1")
        XCTAssertEqual(info.comparableBuildVersion, "200")
        XCTAssertEqual(info.homepage?.absoluteString, "https://example.com")
        XCTAssertTrue(info.appNames.contains("Fixture App.app"))
        XCTAssertTrue(info.appNames.contains("Fixture.app"))
    }
}
