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

    /// The Markdown file currently shown. It changes when a link to another
    /// Markdown file is clicked.
    private var currentFile: URL?

    /// A #heading to scroll to once the page has loaded, e.g. from `other.md#setup`.
    private var pendingFragment: String?

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

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
        pendingHandler = handler
        do {
            try show(url)
        } catch {
            finishLoading(with: error)
        }
    }

    /// Renders a Markdown file into the web view.
    private func show(_ fileURL: URL, scrollingTo fragment: String? = nil) throws {
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let html = MarkdownHTML.page(for: markdown, title: fileURL.lastPathComponent)
        let folder = fileURL.deletingLastPathComponent()

        currentFile = fileURL
        pendingFragment = fragment

        ImageEmbedder.embedImages(in: html, relativeTo: folder) { [weak self] html in
            // The base URL lets relative links resolve against the file's folder.
            self?.webView.loadHTMLString(html, baseURL: folder)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(with: nil)

        if let fragment = pendingFragment {
            pendingFragment = nil
            scroll(to: fragment)
        }
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

    /// Clicked links never navigate the web view itself: web links open in the
    /// browser, and local links are handled by `openLocalLink(_:)`.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        if url.isFileURL {
            openLocalLink(url)
        } else {
            withHelper { $0.openLink(url.absoluteString) }
        }
    }

    // MARK: - Local links

    /// Relative links resolve against the Markdown file's folder, so they arrive as file: URLs.
    ///  - `#setup` scrolls to that heading.
    ///  - `other.md` (or `other.md#setup`) shows that Markdown file in the preview.
    ///  - Anything else, e.g. `LICENSE`, is revealed in Finder. It's never opened,
    ///    because a file could be an app or a script.
    private func openLocalLink(_ url: URL) {
        let target = url.standardizedFileURL
        let fragment = url.fragment.flatMap { $0.removingPercentEncoding ?? $0 }

        if let fragment, let currentFile,
           target.path == currentFile.path || target.path == currentFile.deletingLastPathComponent().path {
            scroll(to: fragment)
            return
        }

        guard FileManager.default.fileExists(atPath: target.path) else { return }

        if Self.markdownExtensions.contains(target.pathExtension.lowercased()) {
            try? show(target, scrollingTo: fragment)
        } else {
            withHelper { $0.revealInFinder(target.path) }
        }
    }

    /// Scrolls to the heading with this id. MarkdownHTML gives headings GitHub-style ids.
    private func scroll(to id: String) {
        // Runs in our isolated world; the id is passed as an argument, never spliced into code.
        webView.callAsyncJavaScript(
            "document.getElementById(id)?.scrollIntoView();",
            arguments: ["id": id],
            in: nil,
            in: .defaultClient
        )
    }

    // MARK: - Helper

    /// Quick Look's sandbox blocks extensions from opening URLs or talking to Finder
    /// (`deny lsopen`), so the ImageFetcher helper does it instead.
    private func withHelper(_ body: (ImageFetcherProtocol) -> Void) {
        let connection = NSXPCConnection(serviceName: ImageEmbedder.helperServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ImageFetcherProtocol.self)
        connection.resume()

        let helper = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("MarkdownQuickLook: helper call failed: %@", String(describing: error))
        } as? ImageFetcherProtocol
        if let helper { body(helper) }

        // These calls have no reply, so give the message a moment to be delivered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            connection.invalidate()
        }
    }

    // MARK: - Syntax highlighting

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

    private func finishLoading(with error: Error?) {
        pendingHandler?(error)
        pendingHandler = nil
    }
}
