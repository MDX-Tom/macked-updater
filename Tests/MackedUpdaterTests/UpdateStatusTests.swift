import XCTest
@testable import MackedUpdater

final class UpdateStatusTests: XCTestCase {
    func testErrorsUseUnifiedUnknownLabel() {
        XCTAssertEqual(UpdateStatus.error.title, "Unknown")
        XCTAssertEqual(UpdateStatus.unknown.title, "Unknown")
    }
}
