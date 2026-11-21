//
//  PreviewViewController.swift
//  MarkdownQuickLook
//
//  Created by Benóný Egilson on 11/19/26.
//

import AppKit
import QuickLookUI
import Markdown

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)

        view = scrollView
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let document = Document(parsing: markdown)
            let rendered = MarkdownTextRenderer().render(document)

            let textView = (view as? NSScrollView)?.documentView as? NSTextView
            textView?.textStorage?.setAttributedString(rendered)

            handler(nil)
        } catch {
            handler(error)
        }
    }
}

private struct MarkdownTextRenderer {
    private let bodyFont = NSFont.systemFont(ofSize: 13)
    private let textColor = NSColor.labelColor

    func render(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")

        for block in document.children {
            // Separate blocks by exactly one blank line. Lists already end
            // with "\n", so only top up to "\n\n" instead of always adding two.
            if result.length > 0 {
                while !result.string.hasSuffix("\n\n") {
                    result.append(makeText("\n", font: bodyFont))
                }
            }
            appendBlock(block, to: result)
        }

        return result
    }

    private func appendBlock(_ markup: Markup, to result: NSMutableAttributedString) {
        if let heading = markup as? Heading {
            let sizes: [CGFloat] = [26, 22, 19, 17, 15, 14]
            let index = min(max(heading.level - 1, 0), sizes.count - 1)
            let font = NSFont.systemFont(ofSize: sizes[index], weight: .bold)

            appendInlineChildren(of: heading, font: font, to: result)
        } else if let paragraph = markup as? Paragraph {
            appendInlineChildren(of: paragraph, font: bodyFont, to: result)
        } else if let list = markup as? UnorderedList {
            appendList(list, startNumber: nil, depth: 0, to: result)
        } else if let list = markup as? OrderedList {
            appendList(list, startNumber: Int(list.startIndex), depth: 0, to: result)
        } else {
            for child in markup.children {
                appendBlock(child, to: result)
            }
        }
    }

    private func appendList(
        _ list: Markup,
        startNumber: Int?,
        depth: Int,
        to result: NSMutableAttributedString
    ) {
        var number = startNumber ?? 1
        let style = listParagraphStyle(depth: depth)

        for child in list.children {
            guard let item = child as? ListItem else { continue }

            let marker = startNumber != nil ? "\(number).\t" : "•\t"
            var styleStart = result.length
            result.append(makeText(marker, font: bodyFont))

            for part in item.children {
                if let paragraph = part as? Paragraph {
                    appendInlineChildren(of: paragraph, font: bodyFont, to: result)
                } else if part is UnorderedList || part is OrderedList {
                    // Style this item's own text before the nested list adds its own.
                    applyStyle(style, from: styleStart, to: result)
                    result.append(makeText("\n", font: bodyFont))
                    let nestedStart = (part as? OrderedList).map { Int($0.startIndex) }
                    appendList(part, startNumber: nestedStart, depth: depth + 1, to: result)
                    styleStart = result.length
                } else {
                    result.append(makeText("\n", font: bodyFont))
                    appendBlock(part, to: result)
                }
            }

            applyStyle(style, from: styleStart, to: result)
            if !result.string.hasSuffix("\n") {
                result.append(makeText("\n", font: bodyFont))
            }
            number += 1
        }
    }

    private func appendInlineChildren(
        of markup: Markup,
        font: NSFont,
        to result: NSMutableAttributedString
    ) {
        for child in markup.children {
            appendInline(child, font: font, to: result)
        }
    }

    private func appendInline(
        _ markup: Markup,
        font: NSFont,
        to result: NSMutableAttributedString
    ) {
        if let text = markup as? Markdown.Text {
            result.append(makeText(text.string, font: font))
        } else if let code = markup as? InlineCode {
            result.append(
                makeText(
                    code.code,
                    font: .monospacedSystemFont(ofSize: 13, weight: .regular)
                )
            )
        } else if markup is SoftBreak {
            result.append(makeText(" ", font: font))
        } else if markup is LineBreak {
            result.append(makeText("\n", font: font))
        } else {
            var childFont = font

            if markup is Strong {
                childFont = NSFontManager.shared.convert(
                    childFont,
                    toHaveTrait: .boldFontMask
                )
            }

            if markup is Emphasis {
                childFont = NSFontManager.shared.convert(
                    childFont,
                    toHaveTrait: .italicFontMask
                )
            }

            for child in markup.children {
                appendInline(child, font: childFont, to: result)
            }
        }
    }

    private func listParagraphStyle(depth: Int) -> NSParagraphStyle {
        let levelIndent: CGFloat = 20
        let markerWidth: CGFloat = 24
        let leading = CGFloat(depth) * levelIndent

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = leading                 // where the marker sits
        style.headIndent = leading + markerWidth            // where wrapped lines start
        style.tabStops = [NSTextTab(textAlignment: .left, location: leading + markerWidth)]
        return style
    }

    private func applyStyle(
        _ style: NSParagraphStyle,
        from start: Int,
        to result: NSMutableAttributedString
    ) {
        guard start < result.length else { return }
        result.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: start, length: result.length - start)
        )
    }

    private func makeText(_ string: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
    }
}
