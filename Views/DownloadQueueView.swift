import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject var model: AppLibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Download Queue", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Clear Finished") {
                    model.clearCompletedDownloads()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!model.downloadQueue.contains { $0.status == .completed || $0.status == .failed })
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.downloadQueue) { item in
                        DownloadQueueCard(item: item)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }
}

private struct DownloadQueueCard: View {
    var item: DownloadQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if item.status == .downloading || item.status == .queued {
                if let progress = item.progressFraction {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("已下载 \(item.downloadedText)")
                    Text("总大小 \(item.totalSizeText)")
                    Text("速度 \(item.status == .downloading ? item.speedText : "—")")
                }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if item.status == .failed {
                Text(item.errorMessage ?? "Failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已下载 \(item.downloadedText)")
                    Text("总大小 \(item.totalSizeText)")
                    Text("速度 —")
                }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(width: 270, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch item.status {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .queued: return .secondary
        case .downloading: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
