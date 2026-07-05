import Foundation

struct AppSettings: Codable, Equatable {
    var autoScanIntervalHours: Int
    var checkOnLaunch: Bool
    var checkHomebrewCask: Bool
    var checkSparkleAppcast: Bool
    var checkMackedApp: Bool
    var excludeSystemApps: Bool

    enum CodingKeys: String, CodingKey {
        case autoScanIntervalHours
        case checkOnLaunch
        case checkHomebrewCask
        case checkSparkleAppcast
        case checkMackedApp
        case excludeSystemApps
    }

    init(
        autoScanIntervalHours: Int,
        checkOnLaunch: Bool,
        checkHomebrewCask: Bool,
        checkSparkleAppcast: Bool,
        checkMackedApp: Bool,
        excludeSystemApps: Bool
    ) {
        self.autoScanIntervalHours = autoScanIntervalHours
        self.checkOnLaunch = checkOnLaunch
        self.checkHomebrewCask = checkHomebrewCask
        self.checkSparkleAppcast = checkSparkleAppcast
        self.checkMackedApp = checkMackedApp
        self.excludeSystemApps = excludeSystemApps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoScanIntervalHours = try container.decodeIfPresent(Int.self, forKey: .autoScanIntervalHours) ?? Self.defaults.autoScanIntervalHours
        checkOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .checkOnLaunch) ?? Self.defaults.checkOnLaunch
        checkHomebrewCask = try container.decodeIfPresent(Bool.self, forKey: .checkHomebrewCask) ?? Self.defaults.checkHomebrewCask
        checkSparkleAppcast = try container.decodeIfPresent(Bool.self, forKey: .checkSparkleAppcast) ?? Self.defaults.checkSparkleAppcast
        checkMackedApp = try container.decodeIfPresent(Bool.self, forKey: .checkMackedApp) ?? Self.defaults.checkMackedApp
        excludeSystemApps = try container.decodeIfPresent(Bool.self, forKey: .excludeSystemApps) ?? Self.defaults.excludeSystemApps
    }

    static let defaults = AppSettings(
        autoScanIntervalHours: 24,
        checkOnLaunch: false,
        checkHomebrewCask: true,
        checkSparkleAppcast: true,
        checkMackedApp: true,
        excludeSystemApps: true
    )
}
