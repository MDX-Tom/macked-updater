import Foundation
import WebKit

struct MackedLoginState: Hashable {
    var isLoggedIn: Bool
    var cookieCount: Int
    var summary: String
}

enum MackedCookieStore {
    @MainActor private static var cachedCookieHeader: String?
    @MainActor private static var cookieHeaderExpiresAt = Date.distantPast
    @MainActor private static var hasCachedCookieHeader = false

    @MainActor
    static func loginState(verifyRemotely: Bool = true) async -> MackedLoginState {
        let cookies = await allCookies()
        let mackedCookies = cookies.filter { $0.domain.contains("macked.app") }
        let header = makeCookieHeader(from: mackedCookies, for: URL(string: "https://macked.app/user")!)
        cachedCookieHeader = header
        cookieHeaderExpiresAt = Date().addingTimeInterval(2 * 60)
        hasCachedCookieHeader = true
        let hasLoginCookie = mackedCookies.contains { cookie in
            cookie.name.lowercased().contains("wordpress_logged_in") ||
                cookie.name.lowercased().contains("zibll") ||
                cookie.name.lowercased().contains("user")
        }

        guard hasLoginCookie else {
            return MackedLoginState(
                isLoggedIn: false,
                cookieCount: mackedCookies.count,
                summary: "Macked.app session not detected"
            )
        }

        if verifyRemotely, let cookieHeader = header {
            do {
                let verified = try await verifySession(cookieHeader: cookieHeader)
                return MackedLoginState(
                    isLoggedIn: verified,
                    cookieCount: mackedCookies.count,
                    summary: verified ? "Macked.app session verified" : "Macked.app session expired"
                )
            } catch {
                return MackedLoginState(
                    isLoggedIn: true,
                    cookieCount: mackedCookies.count,
                    summary: "Macked.app session saved; remote verification unavailable"
                )
            }
        }

        return MackedLoginState(
            isLoggedIn: true,
            cookieCount: mackedCookies.count,
            summary: "Macked.app session saved"
        )
    }

    @MainActor
    static func cookieHeader(for url: URL) async -> String? {
        guard let host = url.host?.lowercased(), host == "macked.app" || host.hasSuffix(".macked.app") else {
            return nil
        }

        if hasCachedCookieHeader, cookieHeaderExpiresAt > Date() {
            return cachedCookieHeader
        }

        let cookies = await allCookies()
        let header = makeCookieHeader(from: cookies, for: url)
        cachedCookieHeader = header
        cookieHeaderExpiresAt = Date().addingTimeInterval(2 * 60)
        hasCachedCookieHeader = true
        return header
    }

    @MainActor
    private static func makeCookieHeader(from cookies: [HTTPCookie], for url: URL) -> String? {
        let applicable = cookies.filter { cookie in
            guard cookie.domain.contains("macked.app") else { return false }
            guard let host = url.host?.lowercased() else { return false }
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return host == domain || host.hasSuffix(".\(domain)")
        }
        guard !applicable.isEmpty else { return nil }
        return applicable.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    @MainActor
    static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func verifySession(cookieHeader: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://macked.app/user")!)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 MackedUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let lowercased = html.lowercased()
        let loggedOutIndicators = [
            "signin-loader",
            "signup-loader",
            "tab-sign-in",
            "user-sign?tab=signin"
        ]
        let loggedInIndicators = [
            "logout",
            "signout",
            "退出登录",
            "个人中心",
            "用户中心",
            "user-center",
            "author-card",
            "profile-header"
        ]

        if loggedInIndicators.contains(where: { lowercased.contains($0.lowercased()) }) {
            return true
        }

        if loggedOutIndicators.contains(where: { lowercased.contains($0.lowercased()) }) {
            return false
        }

        return true
    }
}
