//
//  ImageFetcherProtocol.swift
//  MarkdownQuickLook
//
//  The messages the Quick Look extension can send to this helper.
//  ImageFetcher/ImageFetcherProtocol.swift must declare the same protocol.
//

import Foundation

@objc(ImageFetcherProtocol)
protocol ImageFetcherProtocol {
    /// Downloads each http(s) URL and replies with the image bytes, keyed by URL string.
    /// URLs that fail, time out, or aren't images are left out of the reply.
    func fetchImages(_ urls: [String], reply: @escaping ([String: Data]) -> Void)
}
