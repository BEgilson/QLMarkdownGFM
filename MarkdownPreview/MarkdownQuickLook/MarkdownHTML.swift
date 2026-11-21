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

        let body = HTMLFormatter.format(escaped)

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

/// Rewrites the document so every piece of literal text is HTML-escaped.
/// Raw HTML blocks are left alone on purpose: GitHub renders those as HTML too.
private struct HTMLTextEscaper: MarkupRewriter {
    mutating func visitText(_ text: Markdown.Text) -> Markup? {
        Markdown.Text(MarkdownHTML.escape(text.string))
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineCode(MarkdownHTML.escape(inlineCode.code))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        CodeBlock(language: codeBlock.language, MarkdownHTML.escape(codeBlock.code))
    }
}
