import Foundation

struct UserUpdateSource: Codable, Hashable, Identifiable {
    var appID: String
    var appName: String
    var authorizedCatalogURLString: String
    var officialPageURLString: String
    var appcastURLString: String
    var githubReleasesURLString: String
    var homebrewCaskName: String
    var mackedAppURLString: String
    var mackedSearchQuery: String
    var updatedAt: Date

    var id: String { appID }

    var authorizedCatalogURL: URL? { URL(string: authorizedCatalogURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var officialPageURL: URL? { URL(string: officialPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var appcastURL: URL? { URL(string: appcastURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var githubReleasesURL: URL? { URL(string: githubReleasesURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var mackedAppURL: URL? { URL(string: mackedAppURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var trimmedMackedSearchQuery: String? {
        let value = mackedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    var trimmedHomebrewCaskName: String? {
        let value = homebrewCaskName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var hasAnySource: Bool {
        authorizedCatalogURL != nil ||
            officialPageURL != nil ||
            appcastURL != nil ||
            githubReleasesURL != nil ||
            mackedAppURL != nil ||
            trimmedMackedSearchQuery != nil ||
            trimmedHomebrewCaskName != nil
    }

    init(
        appID: String,
        appName: String,
        authorizedCatalogURLString: String = "",
        officialPageURLString: String,
        appcastURLString: String,
        githubReleasesURLString: String,
        homebrewCaskName: String,
        mackedAppURLString: String = "",
        mackedSearchQuery: String = "",
        updatedAt: Date
    ) {
        self.appID = appID
        self.appName = appName
        self.authorizedCatalogURLString = authorizedCatalogURLString
        self.officialPageURLString = officialPageURLString
        self.appcastURLString = appcastURLString
        self.githubReleasesURLString = githubReleasesURLString
        self.homebrewCaskName = homebrewCaskName
        self.mackedAppURLString = mackedAppURLString
        self.mackedSearchQuery = mackedSearchQuery
        self.updatedAt = updatedAt
    }

    static func empty(for app: InstalledApp) -> UserUpdateSource {
        UserUpdateSource(
            appID: app.id,
            appName: app.name,
            authorizedCatalogURLString: "",
            officialPageURLString: "",
            appcastURLString: "",
            githubReleasesURLString: "",
            homebrewCaskName: "",
            mackedAppURLString: "",
            mackedSearchQuery: "",
            updatedAt: Date()
        )
    }
}

private extension UserUpdateSource {
    enum CodingKeys: String, CodingKey {
        case appID
        case appName
        case authorizedCatalogURLString
        case officialPageURLString
        case appcastURLString
        case githubReleasesURLString
        case homebrewCaskName
        case mackedAppURLString
        case mackedSearchQuery
        case updatedAt
    }
}

extension UserUpdateSource {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decode(String.self, forKey: .appID)
        appName = try container.decode(String.self, forKey: .appName)
        authorizedCatalogURLString = try container.decodeIfPresent(String.self, forKey: .authorizedCatalogURLString) ?? ""
        officialPageURLString = try container.decode(String.self, forKey: .officialPageURLString)
        appcastURLString = try container.decode(String.self, forKey: .appcastURLString)
        githubReleasesURLString = try container.decode(String.self, forKey: .githubReleasesURLString)
        homebrewCaskName = try container.decode(String.self, forKey: .homebrewCaskName)
        mackedAppURLString = try container.decodeIfPresent(String.self, forKey: .mackedAppURLString) ?? ""
        mackedSearchQuery = try container.decodeIfPresent(String.self, forKey: .mackedSearchQuery) ?? ""
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encode(appName, forKey: .appName)
        try container.encode(authorizedCatalogURLString, forKey: .authorizedCatalogURLString)
        try container.encode(officialPageURLString, forKey: .officialPageURLString)
        try container.encode(appcastURLString, forKey: .appcastURLString)
        try container.encode(githubReleasesURLString, forKey: .githubReleasesURLString)
        try container.encode(homebrewCaskName, forKey: .homebrewCaskName)
        try container.encode(mackedAppURLString, forKey: .mackedAppURLString)
        try container.encode(mackedSearchQuery, forKey: .mackedSearchQuery)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
