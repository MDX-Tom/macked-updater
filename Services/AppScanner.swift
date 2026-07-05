import Foundation

struct AppScanner {
    private let fileManager = FileManager.default

    func scanInstalledApps() async -> [InstalledApp] {
        let homeApplications = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let roots: [(url: URL, isSystem: Bool, priority: Int)] = [
            (homeApplications, false, 3),
            (URL(fileURLWithPath: "/Applications", isDirectory: true), false, 2),
            (URL(fileURLWithPath: "/System/Applications", isDirectory: true), true, 1)
        ]

        var appsByID: [String: InstalledApp] = [:]

        for root in roots where fileManager.fileExists(atPath: root.url.path) {
            for app in scanRoot(root.url, isSystem: root.isSystem, priority: root.priority) {
                if let existing = appsByID[app.id] {
                    if shouldReplace(existing: existing, with: app) {
                        appsByID[app.id] = app
                    }
                } else {
                    appsByID[app.id] = app
                }
            }
        }

        return appsByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func scanRoot(_ root: URL, isSystem: Bool, priority: Int) -> [InstalledApp] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var apps: [InstalledApp] = []

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "app" else {
                continue
            }
            if let app = makeInstalledApp(from: url, isSystem: isSystem, priority: priority) {
                apps.append(app)
            }
            enumerator.skipDescendants()
        }

        return apps
    }

    private func makeInstalledApp(from appURL: URL, isSystem: Bool, priority: Int) -> InstalledApp? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let info = plist as? [String: Any]
        else {
            return nil
        }

        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        let executableName = info["CFBundleExecutable"] as? String
        let fileName = appURL.deletingPathExtension().lastPathComponent
        let name = [displayName, bundleName, executableName, fileName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fileName

        let modificationDate = (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let feedString = info["SUFeedURL"] as? String
        let sparkleFeedURL = feedString.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let receiptURL = appURL.appendingPathComponent("Contents/_MASReceipt/receipt")
        let hasReceipt = fileManager.fileExists(atPath: receiptURL.path)

        return InstalledApp(
            name: name,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            shortVersion: info["CFBundleShortVersionString"] as? String,
            buildVersion: info["CFBundleVersion"] as? String,
            installPath: appURL.path,
            isSystemApp: isSystem && !hasReceipt,
            modificationDate: modificationDate,
            sparkleFeedURL: sparkleFeedURL,
            hasMacAppStoreReceipt: hasReceipt,
            scanPriority: priority
        )
    }

    private func shouldReplace(existing: InstalledApp, with candidate: InstalledApp) -> Bool {
        if candidate.scanPriority != existing.scanPriority {
            return candidate.scanPriority > existing.scanPriority
        }

        switch (existing.modificationDate, candidate.modificationDate) {
        case let (.some(left), .some(right)):
            return right > left
        case (.none, .some):
            return true
        default:
            return false
        }
    }
}
