//
//  PreviewViewController.swift
//  MarkdownQuickLook
//
//  Created by Benóný Egilson on 11/19/26.
//

import AppKit
import QuickLookUI
import WebKit

final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!

    /// Quick Look's completion handler, held until the page has finished loading
    /// so Quick Look shows the finished preview instead of a blank view.
    private var pendingHandler: ((Error?) -> Void)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        // Markdown files can contain raw HTML. Never run scripts that come from the file.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        // Our own bundled script still runs: WebKit allows app-injected scripts even
        // with page JavaScript off. It runs in a separate "world", so the page can't
        // see or tamper with it.
        if let highlighter = Self.syntaxHighlightingScript {
            configuration.userContentController.addUserScript(highlighter)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        view = webView
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let html = MarkdownHTML.page(for: markdown, title: url.lastPathComponent)
            let folder = url.deletingLastPathComponent()

            pendingHandler = handler
            ImageEmbedder.embedImages(in: html, relativeTo: folder) { [weak self] html in
                // The base URL lets relative links resolve against the file's folder.
                self?.webView.loadHTMLString(html, baseURL: folder)
            }
        } catch {
            handler(error)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(with: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoading(with: error)
    }

    /// Open clicked links in the default browser instead of inside the preview.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            openLinkThroughHelper(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    /// highlight.js (bundled, BSD-3-Clause) plus a call that colours every code block
    /// that names its language, e.g. ```swift. Like GitHub, unlabelled blocks stay plain.
    private static let syntaxHighlightingScript: WKUserScript? = {
        guard
            let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
            let library = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        let source = library + """

        hljs.configure({ cssSelector: 'pre code[class*="language-"]', ignoreUnescapedHTML: true });
        hljs.highlightAll();
        """

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        )
    }()

    /// Quick Look's sandbox blocks extensions from opening URLs (`deny lsopen`),
    /// so the ImageFetcher helper opens them instead.
    private func openLinkThroughHelper(_ url: URL) {
        let connection = NSXPCConnection(serviceName: ImageEmbedder.helperServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ImageFetcherProtocol.self)
        connection.resume()

        let helper = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("MarkdownQuickLook: couldn't open link: %@", String(describing: error))
        } as? ImageFetcherProtocol
        helper?.openLink(url.absoluteString)

        // openLink has no reply, so give the message a moment to be delivered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            connection.invalidate()
        }
    }

    private func finishLoading(with error: Error?) {
        pendingHandler?(error)
        pendingHandler = nil
    }
}
