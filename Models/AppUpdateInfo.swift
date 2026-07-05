import Foundation

struct AppUpdateInfo: Codable, Hashable, Identifiable {
    var appID: String
    var currentVersion: String?
    var latestVersion: String?
    var officialLatestVersion: String? = nil
    var status: UpdateStatus
    var source: UpdateSource?
    var officialPageURL: URL?
    var officialDownloadURL: URL? = nil
    var officialSourceName: String? = nil
    var officialIsFree: Bool? = nil
    var downloadURL: URL?
    var releaseNotesURL: URL?
    var loginURL: URL? = nil
    var mackedPageURL: URL? = nil
    var mackedDownloadURL: URL? = nil
    var mackedLoginURL: URL? = nil
    var mackedSourceName: String? = nil
    var mackedLatestVersion: String? = nil
    var lastCheckedAt: Date?
    var errorMessage: String?

    var id: String { appID }

    static func unknown(for app: InstalledApp, source: UpdateSource? = nil) -> AppUpdateInfo {
        AppUpdateInfo(
            appID: app.id,
            currentVersion: app.shortVersion,
            latestVersion: nil,
            status: .unknown,
            source: source,
            officialPageURL: source?.pageURL,
            downloadURL: nil,
            releaseNotesURL: nil,
            lastCheckedAt: Date(),
            errorMessage: nil
        )
    }

    static func checking(for app: InstalledApp) -> AppUpdateInfo {
        AppUpdateInfo(
            appID: app.id,
            currentVersion: app.shortVersion,
            latestVersion: nil,
            status: .checking,
            source: nil,
            officialPageURL: nil,
            downloadURL: nil,
            releaseNotesURL: nil,
            lastCheckedAt: nil,
            errorMessage: nil
        )
    }
}
