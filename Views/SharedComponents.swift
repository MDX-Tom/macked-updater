import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum AppIconCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static let fallbackIcon = NSWorkspace.shared.icon(for: .applicationBundle)

    static func cachedIcon(for path: String) -> NSImage? {
        shared.object(forKey: path as NSString)
    }

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = shared.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        shared.setObject(icon, forKey: key)
        return icon
    }
}

struct AppIconView: View {
    var path: String
    var size: CGFloat = 44
    var isSystemApp: Bool = false

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: image ?? AppIconCache.cachedIcon(for: path) ?? AppIconCache.fallbackIcon)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)

            if isSystemApp {
                Image(systemName: "apple.logo")
                    .font(.system(size: max(9, size * 0.22), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 3, y: 2)
            }
        }
        .frame(width: size, height: size)
        .task(id: path) {
            if let cached = AppIconCache.cachedIcon(for: path) {
                image = cached
                return
            }

            let loaded = AppIconCache.icon(for: path)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct StatusBadge: View {
    var status: UpdateStatus

    var body: some View {
        HStack(spacing: 6) {
            if status == .checking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.62)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: 10.5, weight: .semibold))
            }

            Text(status.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(status.tintColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.backgroundColor, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MackedIncludedBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(compact ? "Macked" : "Macked Included")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.green)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.13), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }
}

struct VersionComparisonView: View {
    var currentVersion: String
    var latestVersion: String?
    var status: UpdateStatus = .unknown

    var body: some View {
        HStack(spacing: 12) {
            VersionTile(title: "Current", value: currentVersion, tint: .primary)

            VersionTile(
                title: "Latest",
                value: latestVersion ?? "Unknown",
                tint: status.tintColor,
                isHighlighted: latestVersion != nil,
                highlightColor: status.tintColor
            )
        }
    }
}

struct VersionTile: View {
    var title: String
    var value: String
    var tint: Color = .primary
    var isHighlighted = false
    var highlightColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tileBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
        }
    }

    private var tileBackground: Color {
        guard isHighlighted else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.65)
        }
        return (highlightColor ?? tint).opacity(0.08)
    }
}

struct DetailMetricTile: View {
    var title: String
    var value: String
    var tint: Color = .primary
    var isHighlighted = false

    var body: some View {
        VersionTile(title: title, value: value, tint: tint, isHighlighted: isHighlighted, highlightColor: tint)
    }
}

struct MackedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.56))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.025), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func mackedCard(cornerRadius: CGFloat = 20, padding: CGFloat = 0) -> some View {
        modifier(MackedCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct ConceptPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .frame(minWidth: 150)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(!isEnabled ? 0.42 : (configuration.isPressed ? 0.72 : 1))
    }
}

struct ConceptSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .frame(minWidth: 130)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 1)
            }
            .opacity(!isEnabled ? 0.42 : (configuration.isPressed ? 0.68 : 1))
    }
}

extension AppUpdateInfo {
    var isMackedIncluded: Bool {
        mackedPageURL != nil
            || mackedDownloadURL != nil
            || mackedSourceName != nil
            || mackedLatestVersion != nil
            || mackedLatestBuildVersion != nil
    }
}

extension UpdateStatus {
    var symbolName: String {
        switch self {
        case .unknown:
            return "questionmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.down.circle.fill"
        case .error:
            return "questionmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown:
            return .orange
        case .checking:
            return .blue
        case .upToDate:
            return .green
        case .updateAvailable:
            return .blue
        case .error:
            return .orange
        }
    }

    var backgroundColor: Color {
        tintColor.opacity(0.13)
    }
}
