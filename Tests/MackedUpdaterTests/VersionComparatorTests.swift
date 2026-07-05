import XCTest
@testable import MackedUpdater

final class VersionComparatorTests: XCTestCase {
    func testComparesSemanticVersions() {
        XCTAssertEqual(
            VersionComparator.compare(current: "1.2.3", latest: "1.2.4"),
            .currentOlder
        )
        XCTAssertEqual(
            VersionComparator.compare(current: "1.2.3", latest: "1.2.3"),
            .equal
        )
        XCTAssertEqual(
            VersionComparator.compare(current: "2.0", latest: "1.9.9"),
            .currentNewer
        )
    }

    func testComparesPrereleaseAndCalendarVersions() {
        XCTAssertEqual(
            VersionComparator.compare(current: "1.2.3-beta", latest: "1.2.3"),
            .currentOlder
        )
        XCTAssertEqual(
            VersionComparator.compare(current: "2024.12", latest: "2025.1"),
            .currentOlder
        )
    }

    func testUnknownWhenVersionCannotBeComparedSafely() {
        XCTAssertEqual(
            VersionComparator.compare(current: "Sequoia", latest: "Tahoe"),
            .unknown
        )
    }
}
