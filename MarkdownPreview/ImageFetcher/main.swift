//
//  main.swift
//  ImageFetcher
//
//  A small XPC helper that downloads remote images for the Quick Look extension.
//  macOS doesn't let Quick Look extensions use the network, but this helper has
//  its own sandbox with the outgoing-connections entitlement.
//

import AppKit

final class ImageFetcher: NSObject, ImageFetcherProtocol {
    /// Largest image we'll download, so a huge file can't stall the preview.
    private let maxBytes = 15 * 1024 * 1024

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        // Keep downloaded images on disk so the next preview of the same file is instant.
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    func fetchImages(_ urls: [String], reply: @escaping ([String: Data]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String: Data] = [:]

        for string in Set(urls) {
            guard
                let url = URL(string: string),
                url.scheme == "https" || url.scheme == "http"
            else { continue }

            group.enter()
            session.dataTask(with: url) { [maxBytes] data, response, _ in
                defer { group.leave() }

                guard
                    let data, data.count <= maxBytes,
                    let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                    http.mimeType?.hasPrefix("image/") ?? false
                else { return }

                lock.lock()
                results[string] = data
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .global()) {
            reply(results)
        }
    }

    /// Only web and email links. A file: link could point at an app or a script,
    /// and clicking a link in a preview should never launch one.
    private static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    func openLink(_ urlString: String) {
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            Self.openableSchemes.contains(scheme)
        else { return }

        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ path: String) {
        guard path.hasPrefix("/") else { return }
        // XPC messages arrive on a background queue; AppKit wants the main thread.
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ImageFetcherProtocol.self)
        connection.exportedObject = ImageFetcher()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
