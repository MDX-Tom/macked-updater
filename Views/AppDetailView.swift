import AppKit
import SwiftUI

struct AppDetailView: View {
    @ObservedObject var model: AppLibraryViewModel
    @State private var isShowingMackedLogin = false

    var body: some View {
        Group {
            if let app = model.selectedApp {
                detail(for: app, info: model.updateInfo(for: app))
            } else {
                EmptyStateView(
                    title: "Select an App",
                    message: "Choose an installed app to inspect its version and update source.",
                    systemImage: "rectangle.and.text.magnifyingglass"
                )
                .mackedCard(cornerRadius: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(for app: InstalledApp, info: AppUpdateInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(app: app, info: info)

                VersionComparisonView(currentVersion: app.displayVersion, latestVersion: info.latestVersion, status: info.status)

                sourceSummary(app: app, info: info)

                actionPanel(app: app, info: info)

                metadata(app: app, info: info)

                if let error = info.errorMessage, !error.isEmpty {
                    errorPanel(error)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mackedCard(cornerRadius: 20)
        .sheet(isPresented: $isShowingMackedLogin, onDismiss: {
            Task { await model.refreshMackedLoginState(promptIfMissing: false) }
        }) {
            MackedLoginView(initialURL: info.mackedLoginURL ?? MackedAppChecker.makeLoginURL(redirectingTo: info.mackedPageURL ?? URL(string: "https://macked.app")!))
        }
    }

    private func header(app: InstalledApp, info: AppUpdateInfo) -> some View {
        HStack(alignment: .center, spacing: 18) {
            AppIconView(path: app.installPath, size: 86, isSystemApp: app.isSystemManagedApp)

            VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(app.bundleDisplay)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    if info.isMackedIncluded {
                        MackedIncludedBadge()
                    }
                    StatusBadge(status: info.status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceSummary(app: InstalledApp, info: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Sources")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                SourceLine(label: "Official", value: officialSourceText(info))
                SourceLine(label: "Official free", value: officialFreeText(info.officialIsFree))
                SourceLine(label: "Macked.app", value: mackedSourceText(info), tint: info.isMackedIncluded ? .green : .secondary)
                SourceLine(label: "Homebrew", value: homebrewSourceText(info))
            }
        }
    }

    private func actionPanel(app: InstalledApp, info: AppUpdateInfo) -> some View {
        let columns = [GridItem(.adaptive(minimum: 142), spacing: 10, alignment: .leading)]
        let canDownloadMacked = info.mackedDownloadURL != nil || info.mackedPageURL != nil
        let isMackedDownloading = model.isDownloadingMackedUpdate(for: app)

        return VStack(alignment: .leading, spacing: 13) {
            Text("Actions")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                Button {
                    Task { await model.checkSelectedApp() }
                } label: {
                    Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConceptSecondaryButtonStyle())
                .disabled(model.isChecking)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.installPath)])
                } label: {
                    Label("Reveal", systemImage: "finder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConceptSecondaryButtonStyle())

                DetailLinkButton(title: "Official Page", systemImage: "safari", url: info.officialPageURL ?? info.source?.pageURL)
                DetailLinkButton(title: "Official Download", systemImage: "arrow.down.doc", url: info.officialDownloadURL)
                DetailLinkButton(title: "Macked Page", systemImage: "globe", url: info.mackedPageURL)
                DetailLinkButton(title: "Release Notes", systemImage: "doc.text", url: info.releaseNotesURL)

                Button {
                    if model.mackedLoginState.isLoggedIn {
                        Task { await model.refreshMackedLoginState(promptIfMissing: false) }
                    } else {
                        isShowingMackedLogin = true
                    }
                } label: {
                    Label(model.mackedLoginState.isLoggedIn ? "Logged In" : "Macked Login", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConceptSecondaryButtonStyle())

                Button {
                    Task { await model.downloadMackedUpdate(for: app, info: info) }
                } label: {
                    Label(isMackedDownloading ? "Downloading..." : "Download Macked", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConceptPrimaryButtonStyle())
                .disabled(!canDownloadMacked || isMackedDownloading)
            }
        }
    }

    private func metadata(app: InstalledApp, info: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                DetailLine(label: "Bundle ID", value: app.bundleDisplay, selectable: true)
                DetailLine(label: "Install Path", value: app.installPath, selectable: true)
                DetailLine(label: "Build", value: app.buildVersion ?? "Unknown")
                DetailLine(label: "Last checked", value: info.lastCheckedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                DetailLine(label: "Mac App Store", value: app.hasMacAppStoreReceipt ? "Receipt detected" : "Not detected")
            }
        }
    }

    private func errorPanel(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func officialSourceText(_ info: AppUpdateInfo) -> String {
        let sourceName = info.officialSourceName ?? info.source?.name ?? "Unknown"
        if let version = info.officialLatestVersion ?? info.latestVersion {
            return "\(sourceName) · \(version)"
        }
        return sourceName
    }

    private func homebrewSourceText(_ info: AppUpdateInfo) -> String {
        if info.source?.kind == .homebrewCask {
            if let version = info.latestVersion {
                return "Matched · \(version)"
            }
            return "Matched"
        }
        return "Not matched"
    }

    private func mackedSourceText(_ info: AppUpdateInfo) -> String {
        guard info.isMackedIncluded else {
            return "Not found"
        }
        if let version = info.mackedLatestVersion {
            return "Included · \(version)"
        }
        return "Included"
    }

    private func officialFreeText(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Yes" : "No"
    }
}

private struct SourceLine: View {
    var label: String
    var value: String
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundStyle(tint)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct DetailLine: View {
    var label: String
    var value: String
    var selectable: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            if selectable {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct DetailLinkButton: View {
    var title: String
    var systemImage: String
    var url: URL?

    var body: some View {
        Button {
            if let url {
                BrowserOpener.open(url)
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ConceptSecondaryButtonStyle())
        .disabled(url == nil)
    }
}
