import SwiftUI

struct AppListView: View {
    @ObservedObject var model: AppLibraryViewModel

    var body: some View {
        let apps = model.filteredApps
        let selectedID = model.selectedAppID ?? apps.first?.id

        return VStack(spacing: 0) {
            listHeader(count: apps.count)

            Divider()
                .opacity(0.38)

            if apps.isEmpty {
                EmptyStateView(
                    title: "No Apps",
                    message: "Scan installed apps or adjust the current filter.",
                    systemImage: "app.dashed"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        columnHeader
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 5)

                        ForEach(apps) { app in
                            AppListRow(
                                app: app,
                                info: model.updateInfo(for: app),
                                isSelected: selectedID == app.id
                            ) {
                                model.selectedAppID = app.id
                            }
                            .equatable()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mackedCard(cornerRadius: 20)
    }

    private func listHeader(count: Int) -> some View {
        HStack(spacing: 12) {
            TextField("Search apps, bundle IDs, or paths", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
                }

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .separatorColor).opacity(0.16), in: Capsule())
        }
        .padding(16)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("App")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Current")
                .frame(width: 116, alignment: .leading)
            Text("Latest")
                .frame(width: 168, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct AppListRow: View, Equatable {
    var app: InstalledApp
    var info: AppUpdateInfo
    var isSelected: Bool
    var action: () -> Void

    static func == (lhs: AppListRow, rhs: AppListRow) -> Bool {
        lhs.app == rhs.app && lhs.info == rhs.info && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AppIconView(path: app.installPath, size: 46, isSystemApp: app.isSystemManagedApp)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(0)

                        if info.isMackedIncluded {
                            MackedIncludedBadge(compact: true)
                        }
                    }

                    Text(app.bundleDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(app.displayVersion)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.72)
                    .frame(width: 116, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text(info.latestDisplayVersion ?? "Unknown")
                        .font(.caption.monospacedDigit().weight(info.latestVersion == nil ? .regular : .semibold))
                        .foregroundStyle(info.status.tintColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.72)

                    StatusBadge(status: info.status)
                }
                .frame(width: 168, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 72)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.48) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.11) : Color.clear
    }
}
