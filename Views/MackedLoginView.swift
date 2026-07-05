import SwiftUI
import WebKit

struct MackedLoginView: View {
    var initialURL: URL = MackedAppChecker.makeLoginURL(redirectingTo: URL(string: "https://macked.app")!)
    @Environment(\.dismiss) private var dismiss
    @State private var currentURLString = ""
    @State private var loginState = MackedLoginState(isLoggedIn: false, cookieCount: 0, summary: "Checking session...")
    @State private var didScheduleAutoClose = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Macked.app Login")
                        .font(.headline)
                    Text(loginState.summary + " · cookies: \(loginState.cookieCount)")
                        .font(.caption)
                        .foregroundStyle(loginState.isLoggedIn ? .green : .secondary)
                }
                Spacer()
                Button {
                    Task { await refreshLoginState() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
            }
            .padding(12)

            Divider()

            MackedWebLoginView(url: initialURL) { url in
                currentURLString = url?.absoluteString ?? ""
                Task { await refreshLoginState() }
            }

            Divider()

            HStack {
                Text(currentURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(10)
        }
        .frame(minWidth: 980, minHeight: 720)
        .task { await refreshLoginState() }
        .onChange(of: loginState.isLoggedIn) { isLoggedIn in
            scheduleAutoCloseIfNeeded(isLoggedIn: isLoggedIn)
        }
    }

    @MainActor
    private func refreshLoginState() async {
        let state = await MackedCookieStore.loginState(verifyRemotely: false)
        loginState = state
        scheduleAutoCloseIfNeeded(isLoggedIn: state.isLoggedIn)
    }

    @MainActor
    private func scheduleAutoCloseIfNeeded(isLoggedIn: Bool) {
        guard isLoggedIn, !didScheduleAutoClose else {
            return
        }

        didScheduleAutoClose = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            dismiss()
        }
    }
}

private struct MackedWebLoginView: NSViewRepresentable {
    var url: URL
    var onURLChange: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onURLChange: onURLChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onURLChange: (URL?) -> Void

        init(onURLChange: @escaping (URL?) -> Void) {
            self.onURLChange = onURLChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onURLChange(webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onURLChange(webView.url)
        }
    }
}
