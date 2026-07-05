import Foundation

enum SourceValidation {
    static func validationMessages(for source: UserUpdateSource) -> [String] {
        var messages: [String] = []

        validateURLField(
            label: "Authorized catalog URL",
            rawValue: source.authorizedCatalogURLString,
            messages: &messages,
            allowFileURL: true
        )
        validateURLField(
            label: "Official page URL",
            rawValue: source.officialPageURLString,
            messages: &messages
        )
        validateURLField(
            label: "Sparkle appcast URL",
            rawValue: source.appcastURLString,
            messages: &messages
        )
        validateURLField(
            label: "GitHub Releases URL",
            rawValue: source.githubReleasesURLString,
            messages: &messages,
            requiredHostSuffix: "github.com"
        )
        validateURLField(
            label: "Macked.app page URL",
            rawValue: source.mackedAppURLString,
            messages: &messages,
            requiredHostSuffix: "macked.app"
        )

        if let caskName = source.trimmedHomebrewCaskName {
            validateHomebrewCaskName(caskName, messages: &messages)
        }

        return Array(Set(messages)).sorted()
    }

    static func isAllowed(_ source: UserUpdateSource) -> Bool {
        validationMessages(for: source).isEmpty
    }

    static func validationMessages(
        label: String,
        rawURLString: String,
        requiredHostSuffix: String? = nil,
        allowFileURL: Bool = false
    ) -> [String] {
        var messages: [String] = []
        validateURLField(
            label: label,
            rawValue: rawURLString,
            messages: &messages,
            requiredHostSuffix: requiredHostSuffix,
            allowFileURL: allowFileURL
        )
        return messages
    }

    private static func validateURLField(
        label: String,
        rawValue: String,
        messages: inout [String],
        requiredHostSuffix: String? = nil,
        allowFileURL: Bool = false
    ) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            messages.append("\(label) must be a complete URL.")
            return
        }

        let isFileURL = scheme == "file"
        guard scheme == "https" || scheme == "http" || (allowFileURL && isFileURL) else {
            messages.append(allowFileURL ? "\(label) must use http, https, or file." : "\(label) must use http or https.")
            return
        }

        if !isFileURL {
            guard let host = url.host?.lowercased() else {
                messages.append("\(label) must include a host.")
                return
            }

            if let requiredHostSuffix, host != requiredHostSuffix, !host.hasSuffix(".\(requiredHostSuffix)") {
                messages.append("\(label) must point to \(requiredHostSuffix).")
            }
        }
    }

    private static func validateHomebrewCaskName(_ caskName: String, messages: inout [String]) {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if caskName.rangeOfCharacter(from: allowed.inverted) != nil {
            messages.append("Homebrew cask name contains unsupported characters.")
        }
    }
}
