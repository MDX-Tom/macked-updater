import Foundation

struct Catalog: Encodable {
    var schemaVersion: Int
    var sourceName: String
    var apps: [CatalogApp]
}

struct CatalogApp: Encodable {
    var bundleIdentifier: String?
    var appID: String?
    var name: String
    var latestVersion: String
    var buildVersion: String?
    var officialPageURL: String
    var releaseNotesURL: String
    var downloadPageURL: String
}

let fileManager = FileManager.default
let environment = ProcessInfo.processInfo.environment
let catalogBaseURL = (environment["CATALOG_BASE_URL"] ?? "https://updates.example.com/apps")
    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
let catalogSourceName = environment["CATALOG_SOURCE_NAME"] ?? "Authorized Update Catalog"
let roots = [
    fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    URL(fileURLWithPath: "/Applications", isDirectory: true)
]

func slug(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    let folded = value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .map { character -> Character in
            let scalar = character.unicodeScalars.first
            return scalar.map { allowed.contains($0) ? character : "-" } ?? "-"
        }
    let collapsed = String(folded)
        .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return collapsed.isEmpty ? "app" : collapsed
}

func appInfo(from appURL: URL) -> CatalogApp? {
    let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
    guard
        let data = try? Data(contentsOf: infoURL),
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
        let info = plist as? [String: Any]
    else {
        return nil
    }

    let fileName = appURL.deletingPathExtension().lastPathComponent
    let name = [
        info["CFBundleDisplayName"] as? String,
        info["CFBundleName"] as? String,
        info["CFBundleExecutable"] as? String,
        fileName
    ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? fileName
    let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let latestVersion = ((info["CFBundleShortVersionString"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines))
        .flatMap { $0.isEmpty ? nil : $0 } ?? "0"
    let buildVersion = (info["CFBundleVersion"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let pathSlug = slug(bundleIdentifier ?? name)
    let base = "\(catalogBaseURL)/\(pathSlug)"

    return CatalogApp(
        bundleIdentifier: bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil,
        appID: bundleIdentifier?.isEmpty == false ? bundleIdentifier : slug(name),
        name: name,
        latestVersion: latestVersion,
        buildVersion: buildVersion?.isEmpty == false ? buildVersion : nil,
        officialPageURL: base,
        releaseNotesURL: "\(base)/releases/\(slug(latestVersion))",
        downloadPageURL: "\(base)/download"
    )
}

var appsByID: [String: CatalogApp] = [:]

for root in roots where fileManager.fileExists(atPath: root.path) {
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        continue
    }

    for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
        if let app = appInfo(from: url) {
            let key = (app.bundleIdentifier ?? app.name).lowercased()
            appsByID[key] = app
        }
        enumerator.skipDescendants()
    }
}

let catalog = Catalog(
    schemaVersion: 1,
    sourceName: catalogSourceName,
    apps: appsByID.values.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(catalog)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
