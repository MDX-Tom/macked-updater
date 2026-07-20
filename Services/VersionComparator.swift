import Foundation

enum VersionComparisonOutcome: Equatable {
    case currentOlder
    case equal
    case currentNewer
    case unknown
}

enum VersionComparator {
    static func compare(
        current: String?,
        latest: String?,
        currentBuild: String? = nil,
        latestBuild: String? = nil
    ) -> VersionComparisonOutcome {
        let currentDetails = DetailedVersion(version: current, build: currentBuild)
        let latestDetails = DetailedVersion(version: latest, build: latestBuild)

        guard
            let current = currentDetails.version,
            let latest = latestDetails.version,
            !current.isEmpty,
            !latest.isEmpty
        else {
            return .unknown
        }

        if current.caseInsensitiveCompare(latest) == .orderedSame {
            return compareBuild(currentBuild: currentDetails.build, latestBuild: latestDetails.build) ?? .equal
        }

        guard
            let left = ParsedVersion(current),
            let right = ParsedVersion(latest)
        else {
            return .unknown
        }

        let numericComparison = compareNumeric(left.numbers, right.numbers)
        if numericComparison != .orderedSame {
            return numericComparison == .orderedAscending ? .currentOlder : .currentNewer
        }

        let prereleaseComparison = comparePrerelease(left.prerelease, right.prerelease)
        if prereleaseComparison != .orderedSame {
            return prereleaseComparison == .orderedAscending ? .currentOlder : .currentNewer
        }

        return compareBuild(currentBuild: currentDetails.build, latestBuild: latestDetails.build) ?? .equal
    }

    static func isLatestVersionNewer(current: String?, latest: String?, currentBuild: String? = nil, latestBuild: String? = nil) -> Bool? {
        switch compare(current: current, latest: latest, currentBuild: currentBuild, latestBuild: latestBuild) {
        case .currentOlder:
            return true
        case .equal, .currentNewer:
            return false
        case .unknown:
            return nil
        }
    }

    private static func compareNumeric(_ left: [Int], _ right: [Int]) -> ComparisonResult {
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func comparePrerelease(_ left: [String]?, _ right: [String]?) -> ComparisonResult {
        switch (left, right) {
        case (.none, .none):
            return .orderedSame
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case let (.some(lhs), .some(rhs)):
            let count = max(lhs.count, rhs.count)
            for index in 0..<count {
                guard index < lhs.count else { return .orderedAscending }
                guard index < rhs.count else { return .orderedDescending }

                let leftPart = lhs[index]
                let rightPart = rhs[index]
                if let leftNumber = Int(leftPart), let rightNumber = Int(rightPart), leftNumber != rightNumber {
                    return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
                }
                let comparison = leftPart.localizedStandardCompare(rightPart)
                if comparison != .orderedSame {
                    return comparison
                }
            }
            return .orderedSame
        }
    }

    private static func compareBuild(currentBuild: String?, latestBuild: String?) -> VersionComparisonOutcome? {
        guard
            let currentBuild = currentBuild,
            let latestBuild = latestBuild,
            let current = ParsedVersion(currentBuild),
            let latest = ParsedVersion(latestBuild)
        else {
            return nil
        }

        let result = compareNumeric(current.numbers, latest.numbers)
        switch result {
        case .orderedAscending:
            return .currentOlder
        case .orderedDescending:
            return .currentNewer
        case .orderedSame:
            return .equal
        }
    }
}

private struct ParsedVersion {
    var numbers: [Int]
    var prerelease: [String]?

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPrefix: String
        if trimmed.lowercased().hasPrefix("version ") {
            withoutPrefix = String(trimmed.dropFirst("version ".count))
        } else if trimmed.lowercased().hasPrefix("v"), trimmed.dropFirst().first?.isNumber == true {
            withoutPrefix = String(trimmed.dropFirst())
        } else {
            withoutPrefix = trimmed
        }

        let parts = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let numericPart = String(parts.first ?? "")
        let numericStrings = numericPart.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }

        guard !numericStrings.isEmpty else {
            return nil
        }

        numbers = numericStrings.compactMap(Int.init)
        guard numbers.count == numericStrings.count else {
            return nil
        }

        if parts.count > 1 {
            let suffix = String(parts[1]).lowercased()
            prerelease = suffix.split(whereSeparator: { ".+_ ".contains($0) }).map(String.init)
        } else {
            prerelease = nil
        }
    }
}
