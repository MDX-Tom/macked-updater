import Foundation

enum UpdateStatus: String, Codable, CaseIterable, Hashable {
    case unknown
    case checking
    case upToDate
    case updateAvailable
    case error

    var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking"
        case .upToDate:
            return "Up to Date"
        case .updateAvailable:
            return "Update Available"
        case .error:
            return "Unknown"
        }
    }
}
