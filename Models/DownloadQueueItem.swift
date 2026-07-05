import Foundation

enum DownloadQueueStatus: String, Codable, Hashable {
    case queued
    case downloading
    case completed
    case failed

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

struct DownloadQueueItem: Identifiable, Hashable {
    var id: UUID
    var appID: String
    var appName: String
    var sourceURL: URL
    var status: DownloadQueueStatus
    var bytesWritten: Int64
    var totalBytesExpected: Int64?
    var bytesPerSecond: Double?
    var fileURL: URL?
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    var progressFraction: Double? {
        guard let totalBytesExpected, totalBytesExpected > 0 else {
            return nil
        }
        return min(1, max(0, Double(bytesWritten) / Double(totalBytesExpected)))
    }

    var progressText: String {
        "已下载 \(downloadedText) · 总大小 \(totalSizeText) · 速度 \(speedText)"
    }

    var downloadedText: String {
        Self.byteFormatter.string(fromByteCount: bytesWritten)
    }

    var totalSizeText: String {
        if let totalBytesExpected, totalBytesExpected > 0 {
            return Self.byteFormatter.string(fromByteCount: totalBytesExpected)
        }
        return "未知"
    }

    var speedText: String {
        guard let bytesPerSecond, bytesPerSecond > 0 else {
            return "计算中"
        }
        return "\(Self.byteFormatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    var displayName: String {
        fileURL?.lastPathComponent ?? appName
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
