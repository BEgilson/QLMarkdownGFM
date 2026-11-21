# QLMarkdownGFM

A macOS Quick Look extension that previews Markdown files the way GitHub shows them. Select a `.md` file in Finder and press Space.

This is a modern rewrite of [Watson1978/QLMarkdownGFM](https://github.com/Watson1978/QLMarkdownGFM). The original was a Quick Look *generator* plugin, and macOS 15 stopped loading those. This version is a Quick Look *preview extension*, the kind current macOS supports.

## Features

- GitHub Flavored Markdown: tables, task lists, strikethrough, fenced code blocks
- Syntax highlighting for about 35 languages (labelled code blocks only, like GitHub)
- GitHub alerts: `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`
- Bare URLs turn into clickable links
- Images, both next to the Markdown file (`images/screenshot.png`) and on the web
- Light and dark mode, following the system setting
- Links open in your default browser

## Requirements

- macOS 27.2 or later
- Xcode 27.2 or later, to build from source

## Installation

There are no prebuilt releases yet, so build it from source:

1. Clone this repository and open `MarkdownPreview/MarkdownPreview.xcodeproj` in Xcode.
2. Select the **MarkdownPreview** scheme, choose your own team under **Signing & Capabilities** for all three targets, then build (⌘B).
3. Copy `MarkdownPreview.app` from the build products into `/Applications`, then open it once. This registers the extension with macOS.
4. In **System Settings → General → Login Items & Extensions → Quick Look**, make sure **MarkdownQuickLook** is turned on.

If another Markdown Quick Look extension is installed, remove or disable it so macOS uses this one. If previews don't update after reinstalling, run:

```bash
qlmanage -r && qlmanage -r cache
```

## How it works

The project has three targets:

| Target | What it is |
| --- | --- |
| `MarkdownPreview` | The host app. macOS installs the extension through it. |
| `MarkdownQuickLook` | The Quick Look extension. It parses Markdown with [swift-markdown](https://github.com/swiftlang/swift-markdown), turns it into HTML and shows it in a `WKWebView`. |
| `ImageFetcher` | A small XPC service inside the extension. It downloads remote images and opens clicked links, two things the extension isn't allowed to do itself. |

### Security and privacy

macOS runs Quick Look extensions in a strict sandbox, and the design follows from that:

- **Scripts in Markdown files never run.** JavaScript is turned off for page content. Syntax highlighting is the app's own script, running in an isolated WebKit world the page can't reach.
- **Quick Look extensions have no network access.** Remote images are downloaded by the separate `ImageFetcher` helper. It has network access but can't read your files. It only fetches `http(s)` URLs that return images, with a size limit and a timeout, and caches them.
- **Links open through the helper.** Quick Look extensions can't open URLs, so `ImageFetcher` opens clicked links too. It only opens `http`, `https` and `mailto` links, so a link in a preview can never launch an app or a script.
- **Local images need a file-read exception.** By default, the extension can only read the file being previewed. It has a read-only sandbox exception so it can show images next to that file. It only embeds files that really are images. Because of this exception, the extension can't be distributed through the Mac App Store.

## Third-party software

- [swift-markdown](https://github.com/swiftlang/swift-markdown): Apache License 2.0
- [swift-cmark](https://github.com/swiftlang/swift-cmark) (GitHub's cmark-gfm): BSD 2-Clause License
- [highlight.js](https://highlightjs.org) 11.11.1: BSD 3-Clause License. Bundled as `MarkdownQuickLook/highlight.min.js`, with its copyright notice in the file header.

## License

BSD 3-Clause License. See [LICENSE](LICENSE). The original QLMarkdownGFM is Copyright (c) 2018, Watson.
