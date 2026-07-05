import AppKit
import SwiftUI

struct SourcesView: View {
    @ObservedObject var model: AppLibraryViewModel
    @State private var catalogURLString = ""
    @State private var catalogQuery = ""
    @State private var catalogResults: [AuthorizedCatalogSearchResult] = []
    @State private var catalogSearchError: String?
    @State private var isSearchingCatalog = false
    @State private var mackedQuery = ""
    @State private var mackedResults: [MackedSourceResult] = []
    @State private var mackedSearchError: String?
    @State private var isSearchingMacked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.largeTitle.weight(.semibold))
                        Text("Macked.app search, login, and catalog debugging")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.promptForMackedLogin()
                    } label: {
                        Label(model.mackedLoginState.isLoggedIn ? "Macked Logged In" : "Login Macked.app", systemImage: "person.crop.circle")
                    }
                }
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CatalogSearchPanel(
                        catalogURLString: $catalogURLString,
                        query: $catalogQuery,
                        results: catalogResults,
                        errorMessage: catalogSearchError,
                        isSearching: isSearchingCatalog,
                        validationMessages: catalogValidationMessages,
                        onSearch: {
                            Task { await searchCatalog() }
                        }
                    )

                    MackedSearchPanel(
                        query: $mackedQuery,
                        results: mackedResults,
                        errorMessage: mackedSearchError,
                        isSearching: isSearchingMacked,
                        isLoggedIn: model.mackedLoginState.isLoggedIn,
                        onLogin: {
                            model.promptForMackedLogin()
                        },
                        onSearch: {
                            Task { await searchMacked() }
                        }
                    )

                    MackedReplacementPanel()
                }
                .padding(18)
                .frame(maxWidth: 920, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var catalogValidationMessages: [String] {
        SourceValidation.validationMessages(
            label: "Authorized catalog URL",
            rawURLString: catalogURLString,
            allowFileURL: true
        )
    }

    private func searchCatalog() async {
        let messages = catalogValidationMessages
        guard messages.isEmpty else {
            catalogSearchError = messages.joined(separator: " ")
            catalogResults = []
            return
        }

        let trimmedURL = catalogURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let catalogURL = URL(string: trimmedURL) else {
            catalogSearchError = "Authorized catalog URL must be a complete URL."
            catalogResults = []
            return
        }

        isSearchingCatalog = true
        catalogSearchError = nil

        do {
            catalogResults = try await AuthorizedUpdateCatalogChecker().search(
                catalogURL: catalogURL,
                query: catalogQuery
            )
            if catalogResults.isEmpty {
                catalogSearchError = "No catalog results found."
            }
        } catch {
            catalogResults = []
            catalogSearchError = error.localizedDescription
        }

        isSearchingCatalog = false
    }

    private func searchMacked() async {
        guard await model.ensureMackedLogin(for: "Macked.app search") else {
            mackedSearchError = "Login to Macked.app before searching."
            mackedResults = []
            return
        }

        let query = mackedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            mackedSearchError = "Macked.app search keyword is required."
            mackedResults = []
            return
        }

        isSearchingMacked = true
        mackedSearchError = nil

        do {
            let checker = MackedAppChecker()
            let results = try await checker.search(query: query)
            var enriched: [MackedSourceResult] = []
            for result in results.prefix(8) {
                let detail = try? await checker.detail(pageURL: result.detailURL)
                enriched.append(MackedSourceResult(searchResult: result, detail: detail))
            }
            mackedResults = enriched
            if mackedResults.isEmpty {
                mackedSearchError = "No Macked.app results found."
            }
        } catch {
            mackedResults = []
            mackedSearchError = error.localizedDescription
        }

        isSearchingMacked = false
    }

}

private struct MackedReplacementPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-app sources are automatic")
                .font(.headline)
            Text("Per-app source editing has been replaced by Macked.app search/detail parsing. Use Check Now or Check All to resolve the official page, official download page, Macked.app page, and Macked.app download endpoint for each app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct MackedSourceResult: Identifiable, Hashable {
    var searchResult: MackedAppSearchResult
    var detail: MackedAppDetail?

    var id: String { searchResult.id }
}

private struct CatalogSearchPanel: View {
    @Binding var catalogURLString: String
    @Binding var query: String
    var results: [AuthorizedCatalogSearchResult]
    var errorMessage: String?
    var isSearching: Bool
    var validationMessages: [String]
    var onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Authorized Catalog")
                    .font(.headline)
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                TextField("Catalog URL", text: $catalogURLString)
                    .textFieldStyle(.roundedBorder)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                Button {
                    onSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(isSearching || catalogURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validationMessages.isEmpty)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if !results.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(results) { result in
                        CatalogResultRow(result: result)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CatalogResultRow: View {
    var result: AuthorizedCatalogSearchResult

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.callout.weight(.semibold))
                Text(result.bundleIdentifier ?? result.appID ?? "No Identifier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(result.latestVersion)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .separatorColor).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 8) {
                SourceURLButton(title: "Page", systemImage: "safari", url: result.officialPageURL)
                SourceURLButton(title: "Notes", systemImage: "doc.text", url: result.releaseNotesURL)
                SourceURLButton(title: "Download", systemImage: "arrow.down.circle", url: result.downloadURL)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MackedSearchPanel: View {
    @Binding var query: String
    var results: [MackedSourceResult]
    var errorMessage: String?
    var isSearching: Bool
    var isLoggedIn: Bool
    var onLogin: () -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Macked.app Search")
                    .font(.headline)
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                TextField("Search Macked.app by app name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isLoggedIn)
                Button {
                    if isLoggedIn {
                        onSearch()
                    } else {
                        onLogin()
                    }
                } label: {
                    Label(isLoggedIn ? "Search" : "Login Required", systemImage: isLoggedIn ? "magnifyingglass" : "person.crop.circle.badge.exclamationmark")
                }
                .disabled(isSearching || (isLoggedIn && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }

            Text(isLoggedIn ? "Tip: use this panel to debug Macked.app results. Macked download links save directly to ~/Downloads." : "Macked.app search and downloads require a saved in-app WebKit login session.")
                .font(.caption)
                .foregroundStyle(isLoggedIn ? Color.secondary : Color.orange)

            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !results.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(results) { result in
                        MackedResultRow(result: result, isLoggedIn: isLoggedIn, onLogin: onLogin)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct MackedResultRow: View {
    var result: MackedSourceResult
    var isLoggedIn: Bool
    var onLogin: () -> Void
    @State private var isDownloading = false
    @State private var downloadMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.detail?.title ?? result.searchResult.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(result.searchResult.summary ?? result.searchResult.detailURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let version = result.detail?.latestVersion ?? result.searchResult.latestVersion {
                    Text(version)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .separatorColor).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 8) {
                    SourceURLButton(title: "Page", systemImage: "safari", url: result.searchResult.detailURL)
                    SourceURLButton(
                        title: "Login",
                        systemImage: "person.crop.circle",
                        url: result.detail?.loginURL ?? MackedAppChecker.makeLoginURL(redirectingTo: result.searchResult.detailURL),
                        preferredBrowserBundleIdentifier: BrowserOpener.edgeBundleIdentifier
                    )
                    Button {
                        if isLoggedIn {
                            Task { await download() }
                        } else {
                            onLogin()
                        }
                    } label: {
                        Label(isLoggedIn ? (isDownloading ? "Downloading" : "Download") : "Login", systemImage: isLoggedIn ? "arrow.down.circle" : "person.crop.circle")
                    }
                    .disabled(isLoggedIn && (result.detail?.downloadURL == nil || isDownloading))
                }
            }

            if let downloadMessage {
                Text(downloadMessage)
                    .font(.caption)
                    .foregroundStyle(downloadMessage.lowercased().contains("failed") ? .red : .secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @MainActor
    private func download() async {
        guard isLoggedIn else {
            downloadMessage = "Login to Macked.app before downloading."
            onLogin()
            return
        }

        guard let downloadURL = result.detail?.downloadURL else {
            return
        }

        isDownloading = true
        downloadMessage = "Downloading to ~/Downloads..."
        defer { isDownloading = false }

        do {
            let suggestedName = result.detail?.name ?? result.searchResult.name
            let downloadResult = try await MackedDownloadManager.download(
                from: downloadURL,
                suggestedBaseName: suggestedName,
                refererURL: result.searchResult.detailURL
            )
            downloadMessage = "Saved: \(downloadResult.fileURL.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([downloadResult.fileURL])
        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}

private struct SourceURLButton: View {
    var title: String
    var systemImage: String
    var url: URL?
    var preferredBrowserBundleIdentifier: String? = nil

    var body: some View {
        Button {
            if let url {
                BrowserOpener.open(url, preferredBundleIdentifier: preferredBrowserBundleIdentifier)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(url == nil)
    }
}

private struct SourceRow: View {
    var source: UserUpdateSource
    var app: InstalledApp?
    var onEdit: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let app {
                AppIconView(path: app.installPath, size: 42, isSystemApp: app.isSystemManagedApp)
            } else {
                Image(systemName: "app")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(source.appName)
                    .font(.headline)

                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .separatorColor).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                Text("Updated \(source.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(app == nil)

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }

    private var tags: [String] {
        var values: [String] = []
        if source.authorizedCatalogURL != nil { values.append("Catalog") }
        if source.officialPageURL != nil { values.append("Official Page") }
        if source.appcastURL != nil { values.append("Appcast") }
        if source.githubReleasesURL != nil { values.append("GitHub") }
        if source.trimmedHomebrewCaskName != nil { values.append("Homebrew") }
        if source.mackedAppURL != nil || source.trimmedMackedSearchQuery != nil { values.append("Macked.app") }
        return values.isEmpty ? ["Empty"] : values
    }
}
