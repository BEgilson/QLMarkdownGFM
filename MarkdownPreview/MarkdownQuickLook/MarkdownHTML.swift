//
//  MarkdownHTML.swift
//  MarkdownQuickLook
//
//  Turns Markdown source into a complete, styled HTML page.
//

import Foundation
import Markdown

enum MarkdownHTML {
    /// Builds the full HTML page shown in the preview.
    static func page(for markdown: String, title: String) -> String {
        let document = Document(parsing: markdown)

        // swift-markdown's HTMLFormatter writes text and code out unescaped,
        // so escape it first. Otherwise `<div>` inside a code block would be
        // treated as real HTML instead of being shown as text.
        var escaper = HTMLTextEscaper()
        let escaped = escaper.visit(document) ?? document

        let body = HeadingAnchors.apply(to: GitHubAlerts.apply(to: HTMLFormatter.format(escaped)))

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    /// The contents of preview.css, bundled inside the extension.
    private static let stylesheet: String = {
        guard
            let url = Bundle.main.url(forResource: "preview", withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return css
    }()

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Rewrites the document so every piece of literal text is HTML-escaped, and turns
/// bare URLs into links. Raw HTML blocks are left alone on purpose: GitHub renders
/// those as HTML too.
private struct HTMLTextEscaper: MarkupRewriter {
    /// True while visiting the text of a link or image, which must not be autolinked.
    private var insideLink = false

    mutating func visitLink(_ link: Link) -> Markup? {
        insideLink = true
        defer { insideLink = false }
        return defaultVisit(link)
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        insideLink = true
        defer { insideLink = false }
        return defaultVisit(image)
    }

    mutating func visitText(_ text: Markdown.Text) -> Markup? {
        // HTMLFormatter writes a Text node's string out as-is, so the escaped
        // string may also carry the <a> tags for autolinked URLs.
        let html = insideLink
            ? MarkdownHTML.escape(text.string)
            : Autolinker.linkify(text.string)
        return Markdown.Text(html)
    }

    /// HTMLFormatter writes headings as plain text, which loses **bold**, `code` and
    /// links. So format the heading's contents here and hand it one Text node holding
    /// that HTML, which HTMLFormatter then writes out unchanged.
    mutating func visitHeading(_ heading: Heading) -> Markup? {
        guard let rewritten = defaultVisit(heading) as? Heading else { return heading }
        let innerHTML = rewritten.children.map { HTMLFormatter.format($0) }.joined()
        return Heading(level: heading.level, [Markdown.Text(innerHTML)])
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineCode(MarkdownHTML.escape(inlineCode.code))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        CodeBlock(language: codeBlock.language, MarkdownHTML.escape(codeBlock.code))
    }
}

/// Turns bare URLs such as https://example.com or www.example.com into links,
/// like GitHub does. swift-markdown doesn't enable cmark-gfm's autolink extension.
private enum Autolinker {
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"(?:https?://|www\.)[^\s<]+"#,
        options: [.caseInsensitive]
    )

    /// Returns HTML: the text escaped, with each URL wrapped in an <a> tag.
    static func linkify(_ text: String) -> String {
        let nsText = text as NSString
        var html = ""
        var position = 0

        for match in urlPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            // A URL must start a word: "foowww.example.com" isn't one.
            if match.range.location > 0 {
                let previous = nsText.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if previous.rangeOfCharacter(from: .alphanumerics) != nil { continue }
            }

            let url = trimTrailingPunctuation(nsText.substring(with: match.range))
            let urlRange = NSRange(location: match.range.location, length: (url as NSString).length)

            html += MarkdownHTML.escape(nsText.substring(with: NSRange(location: position, length: urlRange.location - position)))

            let href = url.lowercased().hasPrefix("www.") ? "http://" + url : url
            html += "<a href=\"\(MarkdownHTML.escape(href))\">\(MarkdownHTML.escape(url))</a>"

            position = urlRange.location + urlRange.length
        }

        html += MarkdownHTML.escape(nsText.substring(from: position))
        return html
    }

    /// GitHub's rule: trailing punctuation ends the sentence, not the URL, and a
    /// closing ")" only belongs to the URL if it has a matching "(".
    private static func trimTrailingPunctuation(_ url: String) -> String {
        var url = Substring(url)
        while let last = url.last {
            if ".,:;!?\"'*_~".contains(last) {
                url.removeLast()
            } else if last == ")",
                      url.filter({ $0 == ")" }).count > url.filter({ $0 == "(" }).count {
                url.removeLast()
            } else {
                break
            }
        }
        return String(url)
    }
}

/// Turns GitHub alert block quotes into styled callouts:
///
///     > [!NOTE]
///     > Useful information.
///
/// Supported types: NOTE, TIP, IMPORTANT, WARNING, CAUTION.
private enum GitHubAlerts {
    /// The marker must be the first thing in the quote, alone on its line: either
    /// followed by a line break (group 2) or by the end of its paragraph (group 3).
    private static let markerPattern = try! NSRegularExpression(
        pattern: #"<blockquote>\n<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:((?:<br />)?\n)|(</p>\n))"#,
        options: [.caseInsensitive]
    )

    static func apply(to html: String) -> String {
        let result = NSMutableString(string: html)
        let matches = markerPattern.matches(in: html, range: NSRange(location: 0, length: result.length))

        for match in matches.reversed() {
            let kind = result.substring(with: match.range(at: 1)).lowercased()
            let title = kind.prefix(1).uppercased() + kind.dropFirst()
            let markerWasOwnParagraph = match.range(at: 3).location != NSNotFound

            var replacement = "<blockquote class=\"markdown-alert markdown-alert-\(kind)\">\n"
            replacement += "<p class=\"markdown-alert-title\">\(title)</p>\n"
            if !markerWasOwnParagraph {
                replacement += "<p>"   // the rest of the marker's paragraph follows
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
}

/// Gives every heading a GitHub-style id, so links like [Setup](#setup) can jump to it.
/// "Getting Started!" becomes "getting-started"; repeats become "-1", "-2", and so on.
private enum HeadingAnchors {
    private static let headingPattern = try! NSRegularExpression(
        pattern: #"<h([1-6])>(.*?)</h\1>"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let tagPattern = try! NSRegularExpression(pattern: #"<[^>]+>"#)

    static func apply(to html: String) -> String {
        let result = NSMutableString(string: html)
        let matches = headingPattern.matches(in: html, range: NSRange(location: 0, length: result.length))

        // Ids must be numbered in document order, so work them out first.
        var used: [String: Int] = [:]
        let ids: [String] = matches.map { match in
            let base = slug(fromHTML: result.substring(with: match.range(at: 2)))
            let count = used[base, default: 0]
            used[base] = count + 1
            return count == 0 ? base : "\(base)-\(count)"
        }

        // Then insert them from the end, so earlier ranges stay valid.
        for (match, id) in zip(matches, ids).reversed() {
            let level = result.substring(with: match.range(at: 1))
            let openingTag = NSRange(location: match.range.location, length: "<hN>".count)
            result.replaceCharacters(in: openingTag, with: "<h\(level) id=\"\(MarkdownHTML.escape(id))\">")
        }
        return result as String
    }

    private static func slug(fromHTML html: String) -> String {
        let text = tagPattern
            .stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .lowercased()

        return String(text.compactMap { character -> Character? in
            if character == " " { return "-" }
            if character == "-" || character == "_" { return character }
            return character.isLetter || character.isNumber ? character : nil
        })
    }
}
