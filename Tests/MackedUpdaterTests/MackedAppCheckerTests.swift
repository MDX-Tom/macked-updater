import XCTest
@testable import MackedUpdater

final class MackedAppCheckerTests: XCTestCase {
    private func makeApp(
        name: String,
        bundleIdentifier: String?,
        installPath: String,
        isSystemApp: Bool = false,
        hasMacAppStoreReceipt: Bool = false,
        scanPriority: Int? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            shortVersion: "1.0.0",
            buildVersion: "100",
            installPath: installPath,
            isSystemApp: isSystemApp,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: hasMacAppStoreReceipt,
            scanPriority: scanPriority ?? (isSystemApp ? 0 : 2)
        )
    }

    func testParsesSearchResultCard() throws {
        let html = #"""
        <posts class="posts-item ajax-item card">
          <div class="item-thumbnail"><a href="https://macked.app/vibeproxy-ai-mac.html"><img data-src="https://pic.macked.app/static/vibeproxy.webp"></a></div>
          <div class="item-body">
            <h2 class="item-heading"><a href="https://macked.app/vibeproxy-ai-mac.html" data-tippy-content='<div><span class="attr-key">软件名称</span><span class="attr-value">VibeProxy</span><span class="attr-key">软件版本</span><span class="attr-value">1.8.219</span></div>'>VibeProxy 1.8.219</a></h2>
            <div>Claude proxy helper</div>
          </div>
        </posts>
        """#

        let results = MackedAppChecker.parseSearchResults(html: html, baseURL: URL(string: "https://macked.app")!)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "VibeProxy")
        XCTAssertEqual(results.first?.latestVersion, "1.8.219")
        XCTAssertEqual(results.first?.detailURL.absoluteString, "https://macked.app/vibeproxy-ai-mac.html")
    }

    func testParsesAdobeActivationToolSearchCardTitleAndTooltip() throws {
        let html = #"""
        <posts class="posts-item ajax-item card">
          <div class="item-thumbnail"><a href="https://macked.app/adobe-activation-tool-crack.html"><img src="https://macked.app/wp-content/uploads/thumbnail.png"></a></div>
          <div class="item-body">
            <h2 class="item-heading"><a href="https://macked.app/adobe-activation-tool-crack.html" data-tippy-content='<div><div class="flex jsb"><span class="attr-key">软件名称</span><span class="attr-value">Adobe Activation Tool </span></div><div class="flex jsb"><span class="attr-key">软件版本</span><span class="attr-value">1.2.7/2.1.5</span></div><div class="flex jsb"><span class="attr-key">软件类别</span><span class="attr-value"><a href="https://macked.app/programs/system/crack">破解工具</a></span></div></div>'>Adobe Activation Tool 1.2.7/2.1.5</a></h2>
            <div>Adobe 全家桶激活工具/补丁</div>
          </div>
        </posts>
        """#

        let results = MackedAppChecker.parseSearchResults(html: html, baseURL: URL(string: "https://macked.app")!)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Adobe Activation Tool")
        XCTAssertEqual(results.first?.title, "Adobe Activation Tool 1.2.7/2.1.5")
        XCTAssertEqual(results.first?.latestVersion, "1.2.7/2.1.5")
        XCTAssertEqual(results.first?.detailURL.absoluteString, "https://macked.app/adobe-activation-tool-crack.html")
    }

    func testParsesRESTSearchResults() throws {
        let json = #"""
        [
          {
            "id": 6869,
            "title": "AnyGo 8.3.5 \u7834\u89e3\u7248 &#8211; iOS\u5b9a\u4f4d\u4fee\u6539\u5de5\u5177",
            "url": "https:\/\/macked.app\/anygo-mac-crack.html",
            "type": "post",
            "subtype": "post"
          }
        ]
        """#.data(using: .utf8)!

        let results = try MackedAppChecker.parseRESTSearchResults(
            data: json,
            baseURL: URL(string: "https://macked.app")!
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "AnyGo")
        XCTAssertEqual(results.first?.latestVersion, "8.3.5")
        XCTAssertEqual(results.first?.detailURL.absoluteString, "https://macked.app/anygo-mac-crack.html")
    }

    func testParsesDetailedIMazingVersionFromRESTSearch() throws {
        let json = #"""
        [
          {
            "id": 13756,
            "title": "iMazing 3 3.5.5-24057 \u7834\u89e3\u7248",
            "url": "https:\/\/macked.app\/imazing-3-crack.html",
            "type": "post",
            "subtype": "post"
          }
        ]
        """#.data(using: .utf8)!

        let result = try XCTUnwrap(
            MackedAppChecker.parseRESTSearchResults(
                data: json,
                baseURL: URL(string: "https://macked.app")!
            ).first
        )

        XCTAssertEqual(result.name, "iMazing 3")
        XCTAssertEqual(result.latestVersion, "3.5.5")
        XCTAssertEqual(result.latestBuildVersion, "24057")
    }

    func testBestMatchRejectsAppleBundleFalsePositives() {
        let checker = MackedAppChecker()
        let launcher = makeApp(
            name: "App Store Connect",
            bundleIdentifier: "com.apple.apps.launcher",
            installPath: "/Applications/App Store Connect.app"
        )
        let automator = makeApp(
            name: "Automator",
            bundleIdentifier: "com.apple.Automator",
            installPath: "/System/Applications/Automator.app",
            isSystemApp: true
        )
        let blitz = MackedAppSearchResult(
            name: "Blitz Automate App Store Connect",
            title: "Blitz Automate App Store Connect 1.5.0",
            latestVersion: "1.5.0",
            detailURL: URL(string: "https://macked.app/blitz-automate-app-store-connect-mac.html")!,
            imageURL: nil,
            summary: nil
        )
        let appleRemoteDesktop = MackedAppSearchResult(
            name: "Apple Remote Desktop",
            title: "Apple Remote Desktop 3.9.8",
            latestVersion: "3.9.8",
            detailURL: URL(string: "https://macked.app/apple-remote-desktop-crack.html")!,
            imageURL: nil,
            summary: nil
        )

        XCTAssertFalse(MackedAppChecker.shouldSkipMackedLookup(for: launcher))
        XCTAssertTrue(MackedAppChecker.shouldSkipMackedLookup(for: automator))
        XCTAssertNil(checker.bestMatch(for: launcher, in: [blitz]))
        XCTAssertNil(checker.bestMatch(for: automator, in: [appleRemoteDesktop]))
    }

    func testBestMatchKeepsAnyGoAndAdobeActivationMatches() {
        let checker = MackedAppChecker()
        let anyGo = makeApp(
            name: "iToolab AnyGo",
            bundleIdentifier: "com.itoolab.AnyGoMac",
            installPath: "/Applications/AnyGo.app"
        )
        let anyGoResult = MackedAppSearchResult(
            name: "AnyGo",
            title: "AnyGo 8.3.5",
            latestVersion: "8.3.5",
            detailURL: URL(string: "https://macked.app/anygo-mac-crack.html")!,
            imageURL: nil,
            summary: nil
        )
        let adobeTool = makeApp(
            name: "Adobe Activation Tool",
            bundleIdentifier: "com.example.adobe-activation-tool",
            installPath: "/Applications/Adobe Activation Tool.app"
        )
        let adobeResult = MackedAppSearchResult(
            name: "Adobe Activation Tool",
            title: "Adobe Activation Tool 1.2.7/2.1.5",
            latestVersion: "1.2.7/2.1.5",
            detailURL: URL(string: "https://macked.app/adobe-activation-tool-crack.html")!,
            imageURL: nil,
            summary: nil
        )

        XCTAssertEqual(checker.bestMatch(for: anyGo, in: [anyGoResult])?.detailURL, anyGoResult.detailURL)
        XCTAssertEqual(checker.bestMatch(for: adobeTool, in: [adobeResult])?.detailURL, adobeResult.detailURL)
    }

    func testBestMatchUsesBundleGenerationToChooseIMazing3() {
        let checker = MackedAppChecker()
        let app = InstalledApp(
            name: "iMazing",
            bundleIdentifier: "com.DigiDNA.iMazing3Mac",
            shortVersion: "3.5.5",
            buildVersion: "24057",
            installPath: "/Applications/iMazing.app",
            isSystemApp: false,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: true,
            scanPriority: 2
        )
        let iMazing2 = MackedAppSearchResult(
            name: "iMazing 2",
            title: "iMazing 2 2.17.18.17697",
            latestVersion: "2.17.18.17697",
            detailURL: URL(string: "https://macked.app/imazing-2-crack.html")!,
            imageURL: nil,
            summary: nil
        )
        let iMazing3 = MackedAppSearchResult(
            name: "iMazing 3",
            title: "iMazing 3 3.5.5-24057",
            latestVersion: "3.5.5",
            latestBuildVersion: "24057",
            detailURL: URL(string: "https://macked.app/imazing-3-crack.html")!,
            imageURL: nil,
            summary: nil
        )

        XCTAssertEqual(
            checker.bestMatch(for: app, in: [iMazing2, iMazing3])?.detailURL,
            iMazing3.detailURL
        )
    }

    func testBestMatchKeepsAdobeActivationWhenLocalNameHasNoSpaces() {
        let checker = MackedAppChecker()
        let adobeTool = makeApp(
            name: "AdobeActivationTool",
            bundleIdentifier: "app.macked.Adobe-Activation-Tool",
            installPath: "/Applications/AdobeActivationTool.app"
        )
        let adobeResult = MackedAppSearchResult(
            name: "Adobe Activation Tool",
            title: "Adobe Activation Tool 1.2.7/2.1.5",
            latestVersion: "1.2.7/2.1.5",
            detailURL: URL(string: "https://macked.app/adobe-activation-tool-crack.html")!,
            imageURL: nil,
            summary: nil
        )

        XCTAssertEqual(checker.bestMatch(for: adobeTool, in: [adobeResult])?.detailURL, adobeResult.detailURL)
        XCTAssertEqual(
            MackedAppChecker.knownMackedPageURL(for: adobeTool)?.absoluteString,
            "https://macked.app/adobe-activation-tool-crack.html"
        )
    }

    func testKnownMackedPageRecognizesInstalledAdobeActivationToolBundle() {
        let adobeTool = makeApp(
            name: "Adobe Activation Tool",
            bundleIdentifier: "app.macked.Adobe-Activation-Tool",
            installPath: "/Applications/Adobe Activation Tool.app"
        )

        XCTAssertEqual(
            MackedAppChecker.knownMackedPageURL(for: adobeTool)?.absoluteString,
            "https://macked.app/adobe-activation-tool-crack.html"
        )
        XCTAssertFalse(MackedAppChecker.shouldSkipMackedLookup(for: adobeTool))
    }

    func testAppStoreAppleAppsAreNotTreatedAsSystemManagedForMacked() {
        let finalCut = InstalledApp(
            name: "Final Cut Pro",
            bundleIdentifier: "com.apple.FinalCut",
            shortVersion: "11.1",
            buildVersion: "1",
            installPath: "/Applications/Final Cut Pro.app",
            isSystemApp: true,
            modificationDate: nil,
            sparkleFeedURL: nil,
            hasMacAppStoreReceipt: true,
            scanPriority: 2
        )

        XCTAssertFalse(finalCut.isSystemManagedApp)
        XCTAssertFalse(MackedAppChecker.shouldSkipMackedLookup(for: finalCut))
    }

    func testUserApplicationsPathAppleAppsAreNotSystemManagedEvenWithAppleBundleID() {
        let finalCutCreatorStudio = makeApp(
            name: "Final Cut Pro Creator Studio",
            bundleIdentifier: "com.apple.FinalCutApp",
            installPath: "/Applications/Final Cut Pro Creator Studio.app",
            isSystemApp: true,
            hasMacAppStoreReceipt: false,
            scanPriority: 1
        )

        XCTAssertFalse(finalCutCreatorStudio.isSystemManagedApp)
        XCTAssertFalse(MackedAppChecker.shouldSkipMackedLookup(for: finalCutCreatorStudio))
    }

    @MainActor
    func testMackedCookiesAreNotForwardedToExternalDownloadHosts() async {
        let header = await MackedCookieStore.cookieHeader(for: URL(string: "https://downloads.example.com/file.dmg")!)
        XCTAssertNil(header)
    }

    func testParsesDetailDownloadAndLoginLinks() throws {
        let html = #"""
        <html><head>
          <link rel="canonical" href="https://macked.app/vibeproxy-ai-mac.html" />
          <meta property="og:title" content="VibeProxy 1.8.219 - Claude proxy helper" />
          <meta property="article:modified_time" content="2026-07-03T17:34:15+08:00" />
        </head><body>
          <div class="pay-attr">
            <div class="flex jsb"><span class="attr-key">激活方式</span><span class="attr-value">开源</span></div>
            <div class="flex jsb"><span class="attr-key">软件官网</span><span class="attr-value"><a href=https://github.com/automazeio/vibeproxy>了解更多</a></span></div>
          </div>
          <h2>Download</h2>
          <a target="_blank" href="https://macked.app/wp-content/themes/zibll/zibpay/download.php?post_id=51424&amp;key=5fb35ec0b5&amp;down_id=0">Latest</a>
        </body></html>
        """#

        let detail = try MackedAppChecker.parseDetail(
            html: html,
            pageURL: URL(string: "https://macked.app/vibeproxy-ai-mac.html")!
        )

        XCTAssertEqual(detail.name, "VibeProxy")
        XCTAssertEqual(detail.latestVersion, "1.8.219")
        XCTAssertEqual(detail.pageURL.absoluteString, "https://macked.app/vibeproxy-ai-mac.html")
        XCTAssertEqual(detail.downloadURL?.absoluteString, "https://macked.app/wp-content/themes/zibll/zibpay/download.php?post_id=51424&key=5fb35ec0b5&down_id=0")
        XCTAssertEqual(detail.officialPageURL?.absoluteString, "https://github.com/automazeio/vibeproxy")
        XCTAssertEqual(detail.officialDownloadURL?.absoluteString, "https://github.com/automazeio/vibeproxy/releases/latest")
        XCTAssertEqual(detail.officialSourceName, "GitHub")
        XCTAssertEqual(detail.officialIsFree, true)
        XCTAssertTrue(detail.loginURL.absoluteString.contains("/user-sign?"))
        XCTAssertNotNil(detail.modifiedAt)
    }

    func testParsesDetailedIMazingVersionFromPage() throws {
        let html = #"""
        <html><head>
          <link rel="canonical" href="https://macked.app/imazing-3-crack.html" />
          <meta property="og:title" content="iMazing 3 3.5.5-24057 破解版 - iOS manager" />
        </head><body>
          <div><span class="attr-key">软件版本</span><span class="attr-value">3.5.5-24057</span></div>
        </body></html>
        """#

        let detail = try MackedAppChecker.parseDetail(
            html: html,
            pageURL: URL(string: "https://macked.app/imazing-3-crack.html")!
        )

        XCTAssertEqual(detail.latestVersion, "3.5.5")
        XCTAssertEqual(detail.latestBuildVersion, "24057")
    }

    func testParsesLoggedInDirectDownloadLinkInHiddenContent() throws {
        let html = #"""
        <html><head>
          <link rel="canonical" href="https://macked.app/anygo-mac-crack.html" />
          <meta property="og:title" content="AnyGo 9.2.0 - iOS location changer" />
        </head><body>
          <h2>直链下载</h2>
          <div class="wp-block-zibllblock-hide-content">
            <p><a class="but jb-blue" href="https://dl.example.com/AnyGo_9.2.0.dmg">立即下载</a></p>
          </div>
          <h2>网盘下载</h2>
        </body></html>
        """#

        let detail = try MackedAppChecker.parseDetail(
            html: html,
            pageURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(detail.name, "AnyGo")
        XCTAssertEqual(detail.downloadURL?.absoluteString, "https://dl.example.com/AnyGo_9.2.0.dmg")
    }

    func testDirectDownloadParserIgnoresWebAssets() throws {
        let html = #"""
        <html><head>
          <link rel="canonical" href="https://macked.app/anygo-mac-crack.html" />
          <meta property="og:title" content="AnyGo 9.2.0 - iOS location changer" />
        </head><body>
          <h2>直链下载</h2>
          <div class="wp-block-zibllblock-hide-content">
            <img src="https://macked.app/wp-content/themes/zibll/img/guidance-arrow.svg">
            <p><a class="but jb-blue" href="https://dl.example.com/AnyGo_9.2.0.dmg">立即下载</a></p>
          </div>
          <h2>网盘下载</h2>
        </body></html>
        """#

        let detail = try MackedAppChecker.parseDetail(
            html: html,
            pageURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(detail.downloadURL?.absoluteString, "https://dl.example.com/AnyGo_9.2.0.dmg")
    }

    func testDirectDownloadParserPrefersInstallerDlLinkOverActivationTool() throws {
        let html = #"""
        <html><head>
          <link rel="canonical" href="https://macked.app/anygo-mac-crack.html" />
          <meta property="og:title" content="AnyGo 8.3.5 - iOS location changer" />
        </head><body>
          <h2>直链下载</h2>
          <div class="wp-block-zibllblock-hide-content">
            <a href="https://macked.app/dl/activation-tool-token">激活工具</a>
            <a href="https://macked.app/dl/installer-token">安装包</a>
          </div>
          <h2>网盘下载</h2>
        </body></html>
        """#

        let detail = try MackedAppChecker.parseDetail(
            html: html,
            pageURL: URL(string: "https://macked.app/anygo-mac-crack.html")!
        )

        XCTAssertEqual(detail.downloadURL?.absoluteString, "https://macked.app/dl/installer-token")
    }
}
