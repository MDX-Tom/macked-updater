import Foundation

struct InstalledApp: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var bundleIdentifier: String?
    var shortVersion: String?
    var buildVersion: String?
    var installPath: String
    var isSystemApp: Bool
    var modificationDate: Date?
    var sparkleFeedURL: URL?
    var hasMacAppStoreReceipt: Bool
    var appStoreID: String?
    var scanPriority: Int

    var displayVersion: String {
        DetailedVersion(version: shortVersion, build: buildVersion).displayString ?? "Unknown"
    }

    var bundleDisplay: String {
        bundleIdentifier ?? "No Bundle ID"
    }

    var isSystemManagedApp: Bool {
        guard !hasMacAppStoreReceipt else {
            return false
        }
        if installPath.hasPrefix("/Applications/") || installPath.hasPrefix("\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/") {
            return false
        }
        if installPath.hasPrefix("/System/Applications/") {
            return true
        }
        return isSystemApp && scanPriority <= 1
    }

    init(
        name: String,
        bundleIdentifier: String?,
        shortVersion: String?,
        buildVersion: String?,
        installPath: String,
        isSystemApp: Bool,
        modificationDate: Date?,
        sparkleFeedURL: URL?,
        hasMacAppStoreReceipt: Bool,
        appStoreID: String? = nil,
        scanPriority: Int
    ) {
        let fallback = installPath.lowercased()
        let identifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = (identifier?.isEmpty == false ? identifier! : fallback).lowercased()
        self.name = name
        self.bundleIdentifier = identifier?.isEmpty == false ? identifier : nil
        self.shortVersion = shortVersion?.nilIfBlank
        self.buildVersion = buildVersion?.nilIfBlank
        self.installPath = installPath
        self.isSystemApp = isSystemApp
        self.modificationDate = modificationDate
        self.sparkleFeedURL = sparkleFeedURL
        self.hasMacAppStoreReceipt = hasMacAppStoreReceipt
        self.appStoreID = appStoreID?.nilIfBlank
        self.scanPriority = scanPriority
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
