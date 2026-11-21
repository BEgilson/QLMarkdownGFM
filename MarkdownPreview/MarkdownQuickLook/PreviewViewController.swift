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
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private func finishLoading(with error: Error?) {
        pendingHandler?(error)
        pendingHandler = nil
    }
}
