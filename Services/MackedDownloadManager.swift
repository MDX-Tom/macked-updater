import Foundation
import UniformTypeIdentifiers

struct MackedDownloadResult: Hashable {
    var fileURL: URL
    var responseURL: URL?
    var byteCount: Int64?
}

enum MackedDownloadError: LocalizedError {
    case downloadsDirectoryUnavailable
    case invalidHTTPStatus(Int)
    case htmlResponse(URL?)
    case emptyDownloadedFile
    case redirectLoop(URL?)
    case nonDownloadResponse(URL?, String?)

    var errorDescription: String? {
        switch self {
        case .downloadsDirectoryUnavailable:
            return "Downloads directory is unavailable."
        case .invalidHTTPStatus(let statusCode):
            return "Download request failed with HTTP \(statusCode)."
        case .htmlResponse:
            return "Macked.app returned a web page instead of a file. Refresh the login session and try again."
        case .emptyDownloadedFile:
            return "Downloaded file is empty."
        case .redirectLoop:
            return "Download page redirected too many times."
        case .nonDownloadResponse(_, let mimeType):
            if let mimeType, !mimeType.isEmpty {
                return "Macked.app returned \(mimeType) instead of an installer archive."
            }
            return "Macked.app returned a non-download asset instead of an installer archive."
        }
    }
}

struct MackedDownloadManager {
    static func isWebAssetURL(_ url: URL?) -> Bool {
        guard let url else {
            return false
        }
        return isWebAssetExtension(url.pathExtension.lowercased())
    }

    static func download(from url: URL, suggestedBaseName: String? = nil, refererURL: URL? = nil) async throws -> MackedDownloadResult {
        try await download(from: url, suggestedBaseName: suggestedBaseName, refererURL: refererURL, progress: nil)
    }

    static func download(
        from url: URL,
        suggestedBaseName: String? = nil,
        refererURL: URL? = nil,
        progress: ((Int64, Int64?, Double?) async -> Void)?
    ) async throws -> MackedDownloadResult {
        try await download(from: url, suggestedBaseName: suggestedBaseName, refererURL: refererURL, depth: 0, visited: [], progress: progress)
    }

    private static func download(
        from url: URL,
        suggestedBaseName: String?,
        refererURL: URL?,
        depth: Int,
        visited: Set<String>,
        progress: ((Int64, Int64?, Double?) async -> Void)?
    ) async throws -> MackedDownloadResult {
        let visitKey = canonicalVisitKey(for: url)
        guard depth <= 8, !visited.contains(visitKey) else {
            throw MackedDownloadError.redirectLoop(url)
        }

        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream,text/html;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue((refererURL ?? url.deletingLastPathComponent()).absoluteString, forHTTPHeaderField: "Referer")

        if let cookieHeader = await MackedCookieStore.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (temporaryURL, response) = try await downloadFile(for: request, progress: progress)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            let updatedVisited = visited.union([visitKey])
            if (try? isHTMLResponse(response: response, fileURL: temporaryURL)) == true {
                let html = (try? readHTML(from: temporaryURL)) ?? ""
                if let nextURL = continuationDownloadURL(in: html, baseURL: response.url ?? url, excluding: updatedVisited) {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    return try await download(
                        from: nextURL,
                        suggestedBaseName: suggestedBaseName,
                        refererURL: response.url ?? refererURL ?? url,
                        depth: depth + 1,
                        visited: updatedVisited,
                        progress: progress
                    )
                }
            }
            try? FileManager.default.removeItem(at: temporaryURL)
            throw MackedDownloadError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let downloadedSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard downloadedSize > 0 else {
            throw MackedDownloadError.emptyDownloadedFile
        }

        if try isHTMLResponse(response: response, fileURL: temporaryURL) {
            let html = try readHTML(from: temporaryURL)
            let updatedVisited = visited.union([visitKey])
            if let nextURL = continuationDownloadURL(in: html, baseURL: response.url ?? url, excluding: updatedVisited) {
                try? FileManager.default.removeItem(at: temporaryURL)
                return try await download(
                    from: nextURL,
                    suggestedBaseName: suggestedBaseName,
                    refererURL: response.url ?? refererURL ?? url,
                    depth: depth + 1,
                    visited: updatedVisited,
                    progress: progress
                )
            }
            try? FileManager.default.removeItem(at: temporaryURL)
            throw MackedDownloadError.htmlResponse(response.url)
        }

        guard isLikelyDownloadResponse(response: response, originalURL: url) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw MackedDownloadError.nonDownloadResponse(response.url, response.mimeType)
        }

        let downloadsDirectory = try downloadsDirectoryURL()
        let filename = normalizedDiskImageFilename(
            resolvedFilename(from: response, originalURL: url, suggestedBaseName: suggestedBaseName),
            fileURL: temporaryURL
        )
        let destinationURL = uniqueDestinationURL(in: downloadsDirectory, filename: filename)

        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        let byteCount = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        return MackedDownloadResult(fileURL: destinationURL, responseURL: response.url, byteCount: byteCount)
    }

    static func continuationDownloadURL(in html: String, baseURL: URL, excluding visited: Set<String> = []) -> URL? {
        struct Candidate {
            var url: URL
            var score: Int
        }

        var candidates: [Candidate] = []
        var seen: Set<String> = []

        func add(_ rawValue: String, contextScore: Int = 0) {
            let decoded = rawValue.htmlDecodedForMackedDownload
                .replacingOccurrences(of: #"\\/"#, with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let url = normalizedDownloadURL(decoded, baseURL: baseURL),
                isUsableContinuationURL(url, baseURL: baseURL),
                !visited.contains(canonicalVisitKey(for: url)),
                seen.insert(url.absoluteString).inserted
            else {
                return
            }
            candidates.append(Candidate(url: url, score: scoreContinuationURL(url) + contextScore))
        }

        let anchorPatterns = [
            #"<a\b[^>]*href\s*=\s*"([^"]+)"[^>]*>([\s\S]*?)</a>"#,
            #"<a\b[^>]*href\s*=\s*'([^']+)'[^>]*>([\s\S]*?)</a>"#,
            #"<a\b[^>]*href\s*=\s*([^\s>]+)[^>]*>([\s\S]*?)</a>"#
        ]
        for pattern in anchorPatterns {
            for match in regexMatchesWithCaptures(pattern: pattern, in: html) {
                let label = match.dropFirst().first?.strippingHTMLForMackedDownload.htmlDecodedForMackedDownload.lowercased() ?? ""
                var contextScore = 0
                if label.contains("安装包") || label.contains("installer") || label.contains("install") || label.contains("download") || label.contains("下载") {
                    contextScore += 40
                }
                if label.contains("激活") || label.contains("activation") || label.contains("activate") || label.contains("tool") || label.contains("工具") {
                    contextScore -= 35
                }
                add(match.first ?? "", contextScore: contextScore)
            }
        }

        let patterns = [
            #"<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*url=([^"']+)["'][^>]*>"#,
            #"(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']"#,
            #"location\.replace\(\s*["']([^"']+)["']\s*\)"#,
            #"href\s*=\s*"([^"]+)""#,
            #"href\s*=\s*'([^']+)'"#,
            #"\b(?:data-url|data-href|data-download|data-link)\s*=\s*"([^"]+)""#,
            #"\b(?:data-url|data-href|data-download|data-link)\s*=\s*'([^']+)'"#
        ]
        for pattern in patterns {
            for match in regexMatches(pattern: pattern, in: html) {
                add(match)
            }
        }

        for match in rawURLMatches(in: html) {
            add(match)
        }

        return candidates
            .filter { $0.score >= 70 }
            .sorted { $0.score > $1.score }
            .first?
            .url
    }

    static func resolvedFilename(from response: URLResponse, originalURL: URL, suggestedBaseName: String? = nil) -> String {
        let httpResponse = response as? HTTPURLResponse
        let contentDisposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition")
        let mimeType = httpResponse?.mimeType ?? response.mimeType

        let candidates = [
            filename(fromContentDisposition: contentDisposition),
            response.suggestedFilename,
            usefulLastPathComponent(from: response.url),
            usefulLastPathComponent(from: originalURL),
            suggestedBaseName
        ]

        let filename = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !isGenericDownloadName($0) }
            ?? "MackedDownload-\(Self.timestampString())"

        return sanitizeFilename(filename, mimeType: mimeType)
    }

    static func filename(fromContentDisposition header: String?) -> String? {
        guard let header, !header.isEmpty else {
            return nil
        }

        if let encoded = capture(pattern: #"filename\*\s*=\s*(?:"?UTF-8''([^";]+)"?|"?([^";]+)"?)"#, in: header) {
            return encoded.removingPercentEncoding ?? encoded
        }

        if let plain = capture(pattern: #"filename\s*=\s*"([^"]+)""#, in: header)
            ?? capture(pattern: #"filename\s*=\s*([^;]+)"#, in: header) {
            return plain.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }

        return nil
    }

    private static func downloadsDirectoryURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw MackedDownloadError.downloadsDirectoryUnavailable
        }
        return url
    }

    private static func isHTMLResponse(response: URLResponse, fileURL: URL) throws -> Bool {
        let mimeType = (response.mimeType ?? "").lowercased()
        if mimeType.contains("text/html") || mimeType.contains("application/xhtml") {
            return true
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 4096) ?? Data()
        guard let text = String(data: prefix, encoding: .utf8)?.lowercased() else {
            return false
        }
        return text.contains("<!doctype html") || text.contains("<html")
    }

    private static func readHTML(from fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func downloadFile(
        for request: URLRequest,
        progress: ((Int64, Int64?, Double?) async -> Void)?
    ) async throws -> (URL, URLResponse) {
        let delegate = ProgressDownloadDelegate(progress: progress)
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    private static func normalizedDownloadURL(_ rawValue: String, baseURL: URL) -> URL? {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func isUsableContinuationURL(_ url: URL, baseURL: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let absolute = url.absoluteString.lowercased()
        if absolute == baseURL.absoluteString.lowercased()
            || absolute.contains("javascript:")
            || absolute.contains("/user-sign")
            || absolute.contains("signin")
            || absolute.contains("login")
            || absolute.contains("wp-login")
            || absolute.contains("logout")
            || absolute.contains("category/")
            || absolute.contains("tag/")
            || absolute.contains("author/") {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if isWebAssetExtension(ext) {
            return false
        }
        if ["dmg", "iso", "pkg", "zip", "rar", "7z", "tar", "gz", "tgz", "xz"].contains(ext) {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        if host.contains("macked.app") {
            return absolute.contains("download")
                || absolute.contains("zibpay")
                || absolute.contains("/dl/")
                || (absolute.contains("wp-content/uploads") && !isWebAssetExtension(ext))
        }

        return absolute.contains("download")
            || absolute.contains("dl.")
            || absolute.contains("cdn.")
            || absolute.contains("pan.")
            || absolute.contains("drive.")
            || absolute.contains("cloud")
    }

    private static func scoreContinuationURL(_ url: URL) -> Int {
        let ext = url.pathExtension.lowercased()
        let absolute = url.absoluteString.lowercased()
        if ["dmg", "iso", "pkg", "zip"].contains(ext) { return 100 }
        if ["rar", "7z", "tar", "gz", "tgz", "xz"].contains(ext) { return 90 }
        if absolute.contains("/dl/") { return 86 }
        if absolute.contains("download") { return 80 }
        if absolute.contains("dl.") || absolute.contains("cdn.") || absolute.contains("pan.") || absolute.contains("drive.") || absolute.contains("cloud") { return 75 }
        if (url.host?.lowercased().contains("macked.app") ?? false) { return 70 }
        return 50
    }

    static func isLikelyDownloadResponse(response: URLResponse, originalURL: URL) -> Bool {
        let url = response.url ?? originalURL
        let ext = url.pathExtension.lowercased()
        if downloadableExtensions.contains(ext) {
            return true
        }
        if isWebAssetExtension(ext) {
            return false
        }

        let mimeType = (response.mimeType ?? "").lowercased()
        if mimeType.isEmpty {
            return true
        }

        if mimeType.contains("application/octet-stream")
            || mimeType.contains("application/x-apple-diskimage")
            || mimeType.contains("application/x-iso9660-image")
            || mimeType.contains("application/zip")
            || mimeType.contains("application/x-zip")
            || mimeType.contains("application/x-7z")
            || mimeType.contains("application/x-rar")
            || mimeType.contains("application/gzip")
            || mimeType.contains("application/x-tar")
            || mimeType.contains("binary/octet-stream") {
            return true
        }

        if mimeType.hasPrefix("image/")
            || mimeType.hasPrefix("text/")
            || mimeType.contains("javascript")
            || mimeType.contains("json")
            || mimeType.contains("xml")
            || mimeType.contains("font") {
            return false
        }

        return true
    }

    private static func canonicalVisitKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return (components?.url ?? url).absoluteString.lowercased()
    }

    private static let downloadableExtensions: Set<String> = [
        "dmg", "iso", "pkg", "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "app"
    ]

    static func normalizedDiskImageFilename(_ filename: String, fileURL: URL) -> String {
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        guard pathExtension != "dmg", isUDIFDiskImage(fileURL: fileURL) else {
            return filename
        }

        let baseName = (filename as NSString).deletingPathExtension
        let normalizedBaseName = baseName.isEmpty ? filename : baseName
        return "\(normalizedBaseName).dmg"
    }

    private static func isUDIFDiskImage(fileURL: URL) -> Bool {
        guard
            let handle = try? FileHandle(forReadingFrom: fileURL),
            let fileSize = try? handle.seekToEnd(),
            fileSize >= 512
        else {
            return false
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: fileSize - 512)
            let magic = try handle.read(upToCount: 4)
            return magic == Data("koly".utf8)
        } catch {
            return false
        }
    }

    private static func isWebAssetExtension(_ ext: String) -> Bool {
        [
            "svg", "png", "jpg", "jpeg", "gif", "webp", "avif", "ico",
            "css", "js", "map", "woff", "woff2", "ttf", "otf", "eot",
            "html", "htm"
        ].contains(ext)
    }

    private static func usefulLastPathComponent(from url: URL?) -> String? {
        guard let url else {
            return nil
        }
        let component = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return component.isEmpty ? nil : component
    }

    private static func sanitizeFilename(_ filename: String, mimeType: String?) -> String {
        var sanitized = filename
            .replacingOccurrences(of: #"[/:\\\0]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[\u{0000}-\u{001F}\u{007F}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            sanitized = "MackedDownload-\(timestampString())"
        }

        let ext = (sanitized as NSString).pathExtension
        if ext.isEmpty {
            let preferredExtension = mimeType
                .flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
                ?? "download"
            sanitized += ".\(preferredExtension)"
        }

        return sanitized
    }

    private static func isGenericDownloadName(_ filename: String) -> Bool {
        let normalized = filename.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "download"
            || normalized == "download.php"
            || normalized == "index.php"
            || normalized == "index.html"
            || normalized == "download.html"
    }

    private static func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let baseURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let baseName = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension
        for index in 2...999 {
            let candidateName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        let uuidName = pathExtension.isEmpty ? "\(baseName) \(UUID().uuidString)" : "\(baseName) \(UUID().uuidString).\(pathExtension)"
        return directory.appendingPathComponent(uuidName)
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func capture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            guard let captureRange = Range(match.range(at: index), in: value) else {
                continue
            }
            let captured = String(value[captureRange])
            if !captured.isEmpty {
                return captured
            }
        }

        return nil
    }

    private static func regexMatches(pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            for index in 1..<match.numberOfRanges {
                guard let captureRange = Range(match.range(at: index), in: value) else {
                    continue
                }
                let captured = String(value[captureRange])
                if !captured.isEmpty {
                    return captured
                }
            }
            return nil
        }
    }

    private static func regexMatchesWithCaptures(pattern: String, in value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                guard let captureRange = Range(match.range(at: index), in: value) else {
                    return ""
                }
                return String(value[captureRange])
            }
        }
    }

    private static func rawURLMatches(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?:\\?/\\?/[^\s"'<>\\]+"#, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            Range(match.range(at: 0), in: value).map { String(value[$0]) }
        }
    }
}

private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private let progress: ((Int64, Int64?, Double?) async -> Void)?
    private var downloadedFileURL: URL?
    private var lastProgressDate = Date()
    private var lastProgressBytes: Int64 = 0
    private var lastSpeedBytesPerSecond: Double?

    init(progress: ((Int64, Int64?, Double?) async -> Void)?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let progress else {
            return
        }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let now = Date()
        let elapsed = now.timeIntervalSince(lastProgressDate)
        let speed: Double?
        if elapsed >= 0.2 {
            let deltaBytes = max(0, totalBytesWritten - lastProgressBytes)
            speed = Double(deltaBytes) / elapsed
            lastProgressDate = now
            lastProgressBytes = totalBytesWritten
            lastSpeedBytesPerSecond = speed
        } else {
            speed = lastSpeedBytesPerSecond
        }
        Task {
            await progress(totalBytesWritten, expected, speed)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MackedDownload-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: location, to: temporaryURL)
            downloadedFileURL = temporaryURL
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let continuation else {
            return
        }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
            return
        }

        guard let downloadedFileURL, let response = task.response else {
            continuation.resume(throwing: URLError(.badServerResponse))
            return
        }

        continuation.resume(returning: (downloadedFileURL, response))
    }
}

private extension String {
    var strippingHTMLForMackedDownload: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var htmlDecodedForMackedDownload: String {
        var value = self
        let replacements = [
            "&amp;": "&",
            "&#038;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}
