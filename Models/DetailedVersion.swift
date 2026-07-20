import Foundation

struct DetailedVersion: Hashable {
    var version: String?
    var build: String?

    init(version: String?, build: String? = nil, referenceVersion: String? = nil) {
        let trimmedVersion = Self.trimmed(version)
        let trimmedBuild = Self.trimmed(build)

        if let trimmedBuild {
            if let split = Self.splitEmbeddedBuild(from: trimmedVersion, referenceVersion: referenceVersion), split.build == trimmedBuild {
                self.version = split.version
                self.build = trimmedBuild
            } else if let baseVersion = Self.removingKnownBuild(trimmedBuild, from: trimmedVersion) {
                self.version = baseVersion
                self.build = trimmedBuild
            } else {
                self.version = trimmedVersion
                self.build = trimmedBuild
            }
            return
        }

        if let split = Self.splitEmbeddedBuild(from: trimmedVersion, referenceVersion: referenceVersion) {
            self.version = split.version
            self.build = split.build
        } else {
            self.version = trimmedVersion
            self.build = nil
        }
    }

    var displayString: String? {
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return nil
        }
    }

    private static func splitEmbeddedBuild(
        from version: String?,
        referenceVersion: String?
    ) -> (version: String, build: String)? {
        guard let version else {
            return nil
        }

        let numericBuildPatterns = [
            #"^(.+?)[-+]([0-9]{3,})$"#,
            #"^(.+?)\s+[Bb]uild\s*([0-9]{2,})$"#,
            #"^(.+?)\s*\(([0-9]{2,})\)$"#
        ]

        for pattern in numericBuildPatterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..<version.endIndex, in: version)),
                let versionRange = Range(match.range(at: 1), in: version),
                let buildRange = Range(match.range(at: 2), in: version)
            else {
                continue
            }

            let baseVersion = String(version[versionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let build = String(version[buildRange])
            if !baseVersion.isEmpty {
                return (baseVersion, build)
            }
        }

        if let referenceVersion = trimmed(referenceVersion) {
            let prefix = referenceVersion + "."
            if version.hasPrefix(prefix) {
                let suffix = String(version.dropFirst(prefix.count))
                if suffix.count >= 3, suffix.allSatisfy(\.isNumber) {
                    return (referenceVersion, suffix)
                }
            }
        }

        return nil
    }

    private static func removingKnownBuild(_ build: String, from version: String?) -> String? {
        guard let version else {
            return nil
        }

        let escaped = NSRegularExpression.escapedPattern(for: build)
        let pattern = #"^(.+?)(?:[.\-+_ ]|\()"# + escaped + #"\)?$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..<version.endIndex, in: version)),
            let baseRange = Range(match.range(at: 1), in: version)
        else {
            return nil
        }
        let base = String(version[baseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? nil : base
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
