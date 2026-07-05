import AppKit
import Foundation

enum BrowserOpener {
    static let edgeBundleIdentifier = "com.microsoft.edgemac"

    static func open(_ url: URL, preferredBundleIdentifier: String? = nil) {
        if let preferredBundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            return
        }

        NSWorkspace.shared.open(url)
    }
}
