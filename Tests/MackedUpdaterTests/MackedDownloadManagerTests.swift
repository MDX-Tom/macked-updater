import XCTest
@testable import MackedUpdater

final class MackedDownloadManagerTests: XCTestCase {
    func testParsesRFC5987ContentDispositionFilename() {
        let header = "attachment; filename*=UTF-8''VibeProxy%201.8.219.dmg"

        XCTAssertEqual(
            MackedDownloadManager.filename(fromContentDisposition: header),
            "VibeProxy 1.8.219.dmg"
        )
    }

    func testResolvedFilenameSkipsGenericDownloadPHPName() throws {
        let url = URL(string: "https://macked.app/wp-content/themes/zibll/zibpay/download.php?post_id=1")!
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
            )
        )

        let filename = MackedDownloadManager.resolvedFilename(
            from: response,
            originalURL: url,
            suggestedBaseName: "VibeProxy"
        )

        XCTAssertEqual(filename, "VibeProxy.download")
    }

    func testFindsContinuationDownloadURLInHTMLPage() {
        let html = #"""
        <html><body>
          <a href="/user-sign?tab=signin">Login</a>
          <a href="https://cdn.example.com/AnyGo_9.2.0.dmg">Direct Download</a>
        </body></html>
        """#

        let url = MackedDownloadManager.continuationDownloadURL(
            in: html,
            baseURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/AnyGo_9.2.0.dmg")
    }

    func testContinuationIgnoresSelfLinksAndChoosesStrongDownloadCandidate() {
        let html = #"""
        <html><body>
          <a href="https://macked.app/anygo-mac-crack.html">AnyGo page</a>
          <a href="https://cdn.example.com/files/AnyGo_9.2.0.zip">Mirror</a>
        </body></html>
        """#

        let url = MackedDownloadManager.continuationDownloadURL(
            in: html,
            baseURL: URL(string: "https://macked.app/anygo-mac-crack.html")!,
            excluding: ["https://macked.app/anygo-mac-crack.html"]
        )

        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/files/AnyGo_9.2.0.zip")
    }

    func testContinuationIgnoresGuidanceArrowSVGAsset() {
        let html = #"""
        <html><body>
          <img src="https://macked.app/wp-content/themes/zibll/img/guidance-arrow.svg">
          <a href="https://cdn.example.com/files/AnyGo_9.2.0.dmg">Installer</a>
        </body></html>
        """#

        let url = MackedDownloadManager.continuationDownloadURL(
            in: html,
            baseURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/files/AnyGo_9.2.0.dmg")
    }

    func testContinuationPrefersInstallerDlLinkOverActivationTool() {
        let html = #"""
        <html><body>
          <a href="https://macked.app/dl/activation-tool-token">激活工具</a>
          <a href="https://macked.app/dl/installer-token">安装包</a>
        </body></html>
        """#

        let url = MackedDownloadManager.continuationDownloadURL(
            in: html,
            baseURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(url?.absoluteString, "https://macked.app/dl/installer-token")
    }

    func testRejectsSVGFinalResponseAsNonDownload() throws {
        let url = URL(string: "https://macked.app/wp-content/themes/zibll/img/guidance-arrow.svg")!
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/svg+xml"]
            )
        )

        XCTAssertFalse(MackedDownloadManager.isLikelyDownloadResponse(response: response, originalURL: url))
        XCTAssertTrue(MackedDownloadManager.isWebAssetURL(url))
    }

    func testDownloadQueueItemShowsDownloadedTotalAndSpeed() {
        let item = DownloadQueueItem(
            id: UUID(),
            appID: "com.example.anygo",
            appName: "AnyGo",
            sourceURL: URL(string: "https://cdn.example.com/AnyGo.dmg")!,
            status: .downloading,
            bytesWritten: 1_048_576,
            totalBytesExpected: 10_485_760,
            bytesPerSecond: 524_288,
            fileURL: nil,
            errorMessage: nil,
            startedAt: Date(),
            completedAt: nil
        )

        XCTAssertTrue(item.progressText.contains("已下载"))
        XCTAssertTrue(item.progressText.contains("总大小"))
        XCTAssertTrue(item.progressText.contains("速度"))
        XCTAssertEqual(item.progressFraction, 0.1)
    }

    func testUDIFDiskImageWithIsoNameIsSavedAsDmg() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MackedUpdater-\(UUID().uuidString).iso")
        var data = Data(repeating: 0, count: 1024)
        data.replaceSubrange(512..<516, with: Data("koly".utf8))
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            MackedDownloadManager.normalizedDiskImageFilename("anygo_v8_3_5_MacKed.iso", fileURL: url),
            "anygo_v8_3_5_MacKed.dmg"
        )
        XCTAssertEqual(
            MackedDownloadManager.normalizedDiskImageFilename("AnyGo.dmg", fileURL: url),
            "AnyGo.dmg"
        )
    }
}
