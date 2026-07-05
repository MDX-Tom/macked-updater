import Foundation

enum SidebarSelection: String, CaseIterable, Identifiable {
    case allApps
    case updatesAvailable
    case upToDate
    case unknown
    case sources
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allApps:
            return "All Apps"
        case .updatesAvailable:
            return "Updates Available"
        case .upToDate:
            return "Up to Date"
        case .unknown:
            return "Unknown"
        case .sources:
            return "Sources"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .allApps:
            return "square.grid.2x2"
        case .updatesAvailable:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle"
        case .unknown:
            return "questionmark.circle"
        case .sources:
            return "link"
        case .settings:
            return "gearshape"
        }
    }
}
