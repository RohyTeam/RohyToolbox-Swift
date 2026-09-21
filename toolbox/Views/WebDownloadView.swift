//
//  WebDownloadView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import WebKit
import LNPopupUI

/// Shared state between the SwiftUI chrome and the wrapped WKWebView.
@Observable
final class WebBrowserController {
    weak var webView: WKWebView?
    var canGoBack = false
    var canGoForward = false

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
}

/// An in-app browser presented as a large sheet. Downloads triggered inside
/// the page are intercepted and handed to the download manager together with
/// the session's cookies and user agent. Cookies and site data persist in
/// the default website data store; the last visited page is restored.
struct WebDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var controller = WebBrowserController()
    @State private var address = ""
    @State private var urlToLoad: URL?

    var body: some View {
        NavigationStack {
            WebView(urlToLoad: $urlToLoad, controller: controller) { url, headers, suggestedName in
                DownloadManager.shared.add(url: url, headers: headers, fileName: suggestedName)
                dismiss()
            } onNavigate: { url in
                address = url.absoluteString
                UserDefaults.standard.set(url.absoluteString, forKey: "webDownloadLastURL")
            }
            .overlay {
                if urlToLoad == nil {
                    ContentUnavailableView {
                        Label("Browse Web", systemImage: "safari")
                    } description: {
                        Text("Enter a URL below to start browsing.")
                    }
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .navigationTitle("Browse Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        controller.goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(!controller.canGoBack)
                    Button {
                        controller.goForward()
                    } label: {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(!controller.canGoForward)
                    
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    TextField("Enter URL", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(loadAddress)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard urlToLoad == nil else { return }
            if let last = UserDefaults.standard.string(forKey: "webDownloadLastURL") {
                urlToLoad = URL(string: last)
                address = last
            }
        }
    }

    private func loadAddress() {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") {
            text = "https://" + text
        }
        urlToLoad = URL(string: text)
    }
}

private struct WebView: UIViewRepresentable {
    @Binding var urlToLoad: URL?
    let controller: WebBrowserController
    let onDownload: (URL, [String: String], String?) -> Void
    let onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDownload: onDownload, onNavigate: onNavigate)
    }

    func makeUIView(context: Context) -> WKWebView {
        // The default data store persists cookies and other site data
        // across app launches.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        controller.webView = webView
        context.coordinator.controller = controller
        // KVO catches every URL change: redirects, link taps and SPA
        // pushState navigation alike.
        context.coordinator.urlObservation = webView.observe(\.url, options: [.new]) { _, change in
            guard let url = change.newValue ?? nil else { return }
            Task { @MainActor in
                context.coordinator.onNavigate(url)
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only react to URLs submitted through the address bar. In-page
        // navigation (link taps, redirects, downloads) must never trigger
        // a reload here.
        guard let url = urlToLoad, url != context.coordinator.lastSubmittedURL else { return }
        context.coordinator.lastSubmittedURL = url
        webView.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        weak var webView: WKWebView?
        var controller: WebBrowserController?
        /// The last URL submitted through the address bar.
        var lastSubmittedURL: URL?
        var urlObservation: NSKeyValueObservation?
        let onDownload: (URL, [String: String], String?) -> Void
        let onNavigate: (URL) -> Void
        /// URLs whose navigation was a POST; downloads of these cannot be
        /// replayed by the manager and go through WKDownload instead.
        private var postURLs: Set<String> = []
        private var downloads: [ObjectIdentifier: URL?] = [:]
        private var downloadFileNames: [ObjectIdentifier: String] = [:]

        init(
            onDownload: @escaping (URL, [String: String], String?) -> Void,
            onNavigate: @escaping (URL) -> Void
        ) {
            self.onDownload = onDownload
            self.onNavigate = onNavigate
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            let request = navigationAction.request
            if let url = request.url {
                if (request.httpMethod ?? "GET") == "POST" {
                    postURLs.insert(url.absoluteString)
                } else {
                    postURLs.remove(url.absoluteString)
                }
            }
            // WebKit already knows this action is a file download.
            if navigationAction.shouldPerformDownload, let url = request.url {
                if let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http"),
                   (request.httpMethod ?? "GET") == "GET" {
                    // Plain GET: intercept and download with the manager
                    // (segmented, resumable).
                    decisionHandler(.cancel)
                    intercept(url: url, from: webView)
                } else {
                    // POST / blob downloads cannot be replayed by the
                    // manager; let WebKit download them.
                    decisionHandler(.download)
                }
                return
            }
            // Links that would open a new window stay in this web view.
            if navigationAction.targetFrame == nil, request.url != nil {
                loadInPlace(request, webView: webView)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Replays a new-window navigation in the same web view. WebKit adds
        /// the Referer header only for its own navigations, so manual loads
        /// must carry it explicitly or anti-leech checks redirect to the
        /// site's homepage.
        private func loadInPlace(_ request: URLRequest, webView: WKWebView) {
            var request = request
            if request.value(forHTTPHeaderField: "Referer") == nil,
               let current = webView.url {
                request.setValue(current.absoluteString, forHTTPHeaderField: "Referer")
            }
            webView.load(request)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
        ) {
            guard let http = navigationResponse.response as? HTTPURLResponse,
                  let url = http.url else {
                // Non-HTTP (e.g. blob:) that cannot be displayed: download it
                // through WebKit.
                decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
                return
            }
            let isAttachment = http.value(forHTTPHeaderField: "Content-Disposition")?
                .lowercased().contains("attachment") ?? false
            guard !navigationResponse.canShowMIMEType || isAttachment else {
                decisionHandler(.allow)
                return
            }
            if postURLs.contains(url.absoluteString) {
                // POST download: the manager cannot replay the request body,
                // hand it to WebKit.
                postURLs.remove(url.absoluteString)
                decisionHandler(.download)
                return
            }
            decisionHandler(.cancel)
            intercept(
                url: url,
                from: webView,
                suggestedName: http.value(forHTTPHeaderField: "Content-Disposition")
                    .flatMap(ContentDispositionParser.fileName(from:))
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller?.canGoBack = webView.canGoBack
            controller?.canGoForward = webView.canGoForward
        }

        // MARK: WKUIDelegate (JavaScript window.open)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // No new windows: open the link in the same web view instead.
            if navigationAction.request.url != nil {
                loadInPlace(navigationAction.request, webView: webView)
            }
            return nil
        }

        // MARK: WKDownloadDelegate (POST / blob downloads handled by WebKit)

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            downloads[ObjectIdentifier(download)] = navigationAction.request.url
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
            downloads[ObjectIdentifier(download)] = navigationResponse.response.url
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String
        ) async -> URL? {
            let manager = DownloadManager.shared
            let fileName = manager.uniqueFileName(suggested: suggestedFilename)
            downloads[ObjectIdentifier(download)] = downloads[ObjectIdentifier(download)] ?? response.url
            downloadFileNames[ObjectIdentifier(download)] = fileName
            return manager.destinationURL(forFileName: fileName)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            if let fileName = downloadFileNames[key] {
                DownloadManager.shared.registerCompletedDownload(
                    fileName: fileName,
                    sourceURL: downloads[key] ?? nil
                )
            }
            downloads[key] = nil
            downloadFileNames[key] = nil
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: any Error,
            resumeData: Data?
        ) {
            let key = ObjectIdentifier(download)
            downloads[key] = nil
            downloadFileNames[key] = nil
        }

        /// Hands the download to the manager with the page's session cookies,
        /// user agent and referer attached. `suggestedName` comes from the
        /// response's Content-Disposition header when available.
        private func intercept(url: URL, from webView: WKWebView, suggestedName: String? = nil) {
            let store = webView.configuration.websiteDataStore
            let referer = webView.url?.absoluteString
            webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
                let userAgent = result as? String
                store.httpCookieStore.getAllCookies { cookies in
                    var headers: [String: String] = [:]
                    let cookieHeader = Self.cookieHeader(for: url, cookies: cookies)
                    if !cookieHeader.isEmpty {
                        headers["Cookie"] = cookieHeader
                    }
                    if let userAgent {
                        headers["User-Agent"] = userAgent
                    }
                    if let referer {
                        headers["Referer"] = referer
                    }
                    self?.onDownload(url, headers, suggestedName)
                }
            }
        }

        private static func cookieHeader(for url: URL, cookies: [HTTPCookie]) -> String {
            guard let host = url.host?.lowercased() else { return "" }
            return cookies
                .filter { cookie in
                    let domain = cookie.domain.lowercased()
                    let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
                    return host == bare || host.hasSuffix("." + bare)
                }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
    }
}

#Preview {
    WebDownloadView()
}
