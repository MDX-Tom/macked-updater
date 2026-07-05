import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppLibraryViewModel

    private let primaryItems: [SidebarSelection] = [.allApps, .updatesAvailable, .upToDate, .unknown]
    private let secondaryItems: [SidebarSelection] = [.sources, .settings]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandHeader
                .padding(.top, 28)
                .padding(.horizontal, 18)

            VStack(spacing: 8) {
                ForEach(primaryItems) { item in
                    SidebarRow(item: item, count: model.count(for: item), isSelected: model.selection == item) {
                        model.selection = item
                    }
                }
            }
            .padding(.horizontal, 12)

            VStack(spacing: 8) {
                ForEach(secondaryItems) { item in
                    SidebarRow(item: item, count: item == .sources ? model.count(for: item) : nil, isSelected: model.selection == item) {
                        model.selection = item
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Text("Local data only")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor).opacity(0.92), Color(nsColor: .controlBackgroundColor).opacity(0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("Macked Updater")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct SidebarRow: View {
    var item: SidebarSelection
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 19)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(item.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let count {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .separatorColor).opacity(0.16)),
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            isSelected ? Color.accentColor.opacity(0.13) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.title)
    }
}
