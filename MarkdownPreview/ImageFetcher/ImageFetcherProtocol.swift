//
//  ImageFetcherProtocol.swift
//  ImageFetcher
//
//  The messages the Quick Look extension can send to this helper.
//  MarkdownQuickLook/ImageFetcherProtocol.swift must declare the same protocol.
//

import Foundation

@objc(ImageFetcherProtocol)
protocol ImageFetcherProtocol {
    /// Downloads each http(s) URL and replies with the image bytes, keyed by URL string.
    /// URLs that fail, time out, or aren't images are left out of the reply.
    func fetchImages(_ urls: [String], reply: @escaping ([String: Data]) -> Void)

    /// Opens a clicked link in the default app. Quick Look extensions aren't allowed
    /// to open URLs themselves. Only http, https and mailto links are opened.
    func openLink(_ url: String)

    /// Selects a local file in Finder, for links to files that aren't Markdown.
    /// The file is only shown, never opened.
    func revealInFinder(_ path: String)
}
