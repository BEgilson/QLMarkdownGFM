//
//  ImageEmbedder.swift
//  MarkdownQuickLook
//
//  Quick Look extensions can't load images by URL themselves: they have no
//  network access, and the web view can't read files next to the previewed one.
//  So every <img src="…"> is resolved here and replaced with a data: URL that
//  contains the image bytes.
//

import Foundation
import UniformTypeIdentifiers

enum ImageEmbedder {
    static let helperServiceName = "Frontal.MarkdownPreview.MarkdownQuickLook.ImageFetcher"

    /// Give up on remote images after this long, so an offline Mac doesn't hang the preview.
    private static let remoteTimeout: TimeInterval = 12

    /// Matches <img … src="…"> or src='…'. Group 3 is the source value.
    private static let imageSourcePattern = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    /// Calls `completion` on the main thread with the HTML, its images embedded.
    static func embedImages(
        in html: String,
        relativeTo baseURL: URL,
        completion: @escaping (String) -> Void
    ) {
        var embedded: [String: String] = [:]   // original src → data: URL
        var remote: [String: String] = [:]     // absolute URL → original src

        for source in imageSources(in: html) {
            // Raw HTML may write & as &amp; inside attributes.
            let decoded = source.replacingOccurrences(of: "&amp;", with: "&")

            if decoded.lowercased().hasPrefix("data:") { continue }

            if let url = URL(string: decoded),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                remote[url.absoluteString] = source
            } else if let fileURL = localFileURL(for: decoded, relativeTo: baseURL),
                      let data = try? Data(contentsOf: fileURL),
                      // The extension may read any file (see MarkdownQuickLook.entitlements),
                      // so only ever embed files that really are images.
                      mimeType(for: data, pathExtension: fileURL.pathExtension).hasPrefix("image/") {
                embedded[source] = dataURL(for: data, pathExtension: fileURL.pathExtension)
            }
        }

        guard !remote.isEmpty else {
            let result = replacingSources(in: html, with: embedded)
            DispatchQueue.main.async { completion(result) }
            return
        }

        fetchRemoteImages(Array(remote.keys)) { downloads in
            var all = embedded
            for (urlString, data) in downloads {
                guard let source = remote[urlString] else { continue }
                let pathExtension = URL(string: urlString)?.pathExtension ?? ""
                all[source] = dataURL(for: data, pathExtension: pathExtension)
            }
            completion(replacingSources(in: html, with: all))
        }
    }

    // MARK: - Finding and replacing sources

    private static func imageSources(in html: String) -> [String] {
        let range = NSRange(html.startIndex..., in: html)
        return imageSourcePattern.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 3), in: html).map { String(html[$0]) }
        }
    }

    private static func replacingSources(in html: String, with replacements: [String: String]) -> String {
        guard !replacements.isEmpty else { return html }

        let result = NSMutableString(string: html)
        let range = NSRange(location: 0, length: result.length)

        // Replace from the end so earlier ranges stay valid.
        for match in imageSourcePattern.matches(in: html, range: range).reversed() {
            let sourceRange = match.range(at: 3)
            let source = result.substring(with: sourceRange)
            if let replacement = replacements[source] {
                result.replaceCharacters(in: sourceRange, with: replacement)
            }
        }
        return result as String
    }

    // MARK: - Local images

    private static func localFileURL(for source: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: source), url.scheme != nil {
            return url.isFileURL ? url : nil   // ignore other schemes, e.g. mailto:
        }
        // Drop any ?query or #fragment, then undo %20-style escapes.
        let path = source.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
        let unescaped = path.removingPercentEncoding ?? path
        return URL(fileURLWithPath: unescaped, relativeTo: baseURL).standardizedFileURL
    }

    // MARK: - Remote images (through the ImageFetcher helper)

    private static func fetchRemoteImages(
        _ urls: [String],
        completion: @escaping ([String: Data]) -> Void
    ) {
        let connection = NSXPCConnection(serviceName: helperServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ImageFetcherProtocol.self)
        connection.resume()

        // Whichever comes first wins: the reply, an XPC error, or the timeout.
        let lock = NSLock()
        var finished = false
        let finish: ([String: Data]) -> Void = { downloads in
            lock.lock()
            let alreadyFinished = finished
            finished = true
            lock.unlock()
            guard !alreadyFinished else { return }

            connection.invalidate()
            DispatchQueue.main.async { completion(downloads) }
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("MarkdownQuickLook: image helper failed: %@", String(describing: error))
            finish([:])
        } as? ImageFetcherProtocol

        guard let proxy else {
            finish([:])
            return
        }

        proxy.fetchImages(urls) { downloads in finish(downloads) }
        DispatchQueue.main.asyncAfter(deadline: .now() + remoteTimeout) { finish([:]) }
    }

    // MARK: - data: URLs

    private static func dataURL(for data: Data, pathExtension: String) -> String {
        "data:\(mimeType(for: data, pathExtension: pathExtension));base64,\(data.base64EncodedString())"
    }

    /// Prefer the file's actual bytes over its name: badge URLs, for example,
    /// often serve SVG with no file extension.
    private static func mimeType(for data: Data, pathExtension: String) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.count >= 12, bytes[8...11] == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }

        let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        if head.contains("<svg") { return "image/svg+xml" }

        return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
