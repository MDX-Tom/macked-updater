import Foundation

enum UpdateSourceKind: String, Codable, CaseIterable, Hashable {
    case userConfigured
    case sparkleAppcast
    case homebrewCask
    case macAppStore
    case githubReleases
    case authorizedCatalog
    case mackedApp
    case officialWebsite
    case manualSearch

    var title: String {
        switch self {
        case .userConfigured:
            return "User Source"
        case .sparkleAppcast:
            return "Sparkle Appcast"
        case .homebrewCask:
            return "Homebrew Cask"
        case .macAppStore:
            return "Mac App Store"
        case .githubReleases:
            return "GitHub Releases"
        case .authorizedCatalog:
            return "Authorized Catalog"
        case .mackedApp:
            return "Macked.app"
        case .officialWebsite:
            return "Official Website"
        case .manualSearch:
            return "Web Search"
        }
    }
}

struct UpdateSource: Codable, Hashable, Identifiable {
    var kind: UpdateSourceKind
    var name: String
    var identifier: String?
    var pageURL: URL?
    var feedURL: URL?

    var id: String {
        [kind.rawValue, identifier, pageURL?.absoluteString, feedURL?.absoluteString]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    static func manualSearch(url: URL) -> UpdateSource {
        UpdateSource(
            kind: .manualSearch,
            name: UpdateSourceKind.manualSearch.title,
            identifier: nil,
            pageURL: url,
            feedURL: nil
        )
    }
}
