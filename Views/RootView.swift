import SwiftUI

struct RootView: View {
    @StateObject private var model = AppLibraryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(model: model)
                    .frame(width: 230)

                content
            }

            if !model.downloadQueue.isEmpty {
                Divider()
                DownloadQueueView(model: model)
            }

            statusBar
        }
        .frame(minWidth: 1160, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.bootstrap()
        }
        .sheet(isPresented: $model.isShowingMackedLoginPrompt, onDismiss: {
            Task { await model.refreshMackedLoginState(promptIfMissing: false) }
        }) {
            MackedLoginView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection {
        case .settings:
            SettingsView(model: model)
        case .sources:
            SourcesView(model: model)
        default:
            dashboard
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            dashboardHeader

            HStack(alignment: .top, spacing: 22) {
                AppListView(model: model)
                    .frame(minWidth: 500, idealWidth: 630, maxWidth: .infinity)

                AppDetailView(model: model)
                    .frame(minWidth: 330, idealWidth: 390, maxWidth: 430)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.selection.title)
                    .font(.system(size: 30, weight: .semibold))
                    .lineLimit(1)

                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                rescanControl

                Button {
                    Task { await model.checkAllApps() }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(ConceptPrimaryButtonStyle())
                .focusable(false)
                .disabled(model.isChecking || model.apps.isEmpty)
            }
        }
    }

    private var rescanControl: some View {
        Label("Rescan Apps", systemImage: "magnifyingglass")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .frame(minWidth: 142)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(model.isScanning ? 0.42 : 1)
            .onTapGesture {
                guard !model.isScanning else { return }
                Task { await model.scanApps() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Rescan Apps")
    }

    private var headerSubtitle: String {
        if model.isScanning || model.isChecking {
            return model.statusMessage
        }
        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(model.filteredApps.count) apps shown · \(model.visibleApps.count) visible · \(model.apps.count) scanned"
        }
        return "\(model.filteredApps.count) matches for “\(model.searchText)”"
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isScanning || model.isChecking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if model.settings.checkMackedApp {
                Button {
                    if model.mackedLoginState.isLoggedIn {
                        Task { await model.refreshMackedLoginState(promptIfMissing: false) }
                    } else {
                        model.promptForMackedLogin()
                    }
                } label: {
                    Label(
                        model.mackedLoginState.isLoggedIn ? "Macked Logged In" : "Login Macked.app",
                        systemImage: model.mackedLoginState.isLoggedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(model.mackedLoginState.isLoggedIn ? .green : .orange)
            }

            Text(model.settings.excludeSystemApps ? "\(model.visibleApps.count) shown · \(model.apps.count) scanned" : "\(model.apps.count) apps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
