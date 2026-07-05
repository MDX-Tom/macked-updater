import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppLibraryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))

                SettingsGroup(title: "Update Checks") {
                    Toggle("Check on launch", isOn: $model.settings.checkOnLaunch)
                    Toggle("Check Sparkle appcast", isOn: $model.settings.checkSparkleAppcast)
                    Toggle("Check Homebrew Cask", isOn: $model.settings.checkHomebrewCask)
                    Toggle("Check Macked.app", isOn: $model.settings.checkMackedApp)
                    Toggle("Exclude system apps", isOn: $model.settings.excludeSystemApps)
                    Text("Hides apps from /System/Applications only. App Store apps with com.apple bundle identifiers remain visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper(value: $model.settings.autoScanIntervalHours, in: 1...168) {
                        Text("Auto scan interval: \(model.settings.autoScanIntervalHours) hours")
                    }
                }

                SettingsGroup(title: "Cache") {
                    HStack {
                        Text("Local update cache")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await model.clearCache() }
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                }

                SettingsGroup(title: "Privacy") {
                    Text("Macked Updater scans installed apps locally and stores update metadata in Application Support. It does not upload your app list, collect account passwords, install apps, or replace apps. Macked.app login state is kept in the local WebKit website data store. External pages open only after you click a link; Macked.app downloads save to ~/Downloads only after you click Download.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}
