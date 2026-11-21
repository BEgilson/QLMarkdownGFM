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
- Links that work:
  - web and email links open in your default browser or mail app
  - `#heading` links jump to that heading
  - links to other Markdown files (`docs/setup.md`) show that file in the preview
  - links to any other local file (`LICENSE`) select it in Finder, without opening it

## Requirements

- macOS 12 Monterey or later
- Xcode 27.2 or later, to build from source

> [!WARNING]
> QLMarkdownGFM has only been tested on macOS 27. It's built to run on macOS 12 and later, but versions 12 to 26 are untested. If you use one of them, please [open an issue](https://github.com/BEgilson/QLMarkdownGFM/issues) to say whether it works. Include your macOS version, what you tried, and a screenshot if something looks wrong.

## Installation

There are no prebuilt releases yet, so build it from source:

1. Clone this repository and open `MarkdownPreview/MarkdownPreview.xcodeproj` in Xcode.
2. Select the **MarkdownPreview** scheme, choose your own team under **Signing & Capabilities** for all three targets, then build (⌘B).
3. Copy `MarkdownPreview.app` from the build products into `/Applications`, then open it once. This registers the extension with macOS.
4. Make sure **MarkdownQuickLook** is turned on. The app's window has a button that opens the right settings page. Its location depends on your macOS version:
   - macOS 15 and later: **System Settings → General → Login Items & Extensions → Quick Look**
   - macOS 13 and 14: **System Settings → Privacy & Security → Extensions → Quick Look**
   - macOS 12: **System Preferences → Extensions → Quick Look**

If another Markdown Quick Look extension is installed, remove or disable it so macOS uses this one. If previews don't update after reinstalling, run:

```bash
qlmanage -r && qlmanage -r cache
```

## How it works

The project has three targets:

| Target | What it is |
| --- | --- |
| `MarkdownPreview` | The host app. macOS installs the extension through it, and its window explains how to turn the extension on. |
| `MarkdownQuickLook` | The Quick Look extension. It parses Markdown with [swift-markdown](https://github.com/swiftlang/swift-markdown), turns it into HTML and shows it in a `WKWebView`. |
| `ImageFetcher` | A small XPC service inside the extension. It downloads remote images, opens clicked links and selects linked files in Finder, which the extension isn't allowed to do itself. |

### Security and privacy

macOS runs Quick Look extensions in a strict sandbox, and the design follows from that:

- **Scripts in Markdown files never run.** JavaScript is turned off for page content. Syntax highlighting is the app's own script, running in an isolated WebKit world the page can't reach.
- **Quick Look extensions have no network access.** Remote images are downloaded by the separate `ImageFetcher` helper. It has network access but can't read your files. It only fetches `http(s)` URLs that return images, with a size limit and a timeout, and caches them.
- **Links open through the helper.** Quick Look extensions can't open URLs, so `ImageFetcher` opens clicked links too. It only opens `http`, `https` and `mailto` links. Links to local files are only ever shown in the preview (Markdown) or selected in Finder (anything else), so a link in a preview can never launch an app or a script.
- **Local images need a file-read exception.** By default, the extension can only read the file being previewed. It has a read-only sandbox exception so it can show images next to that file. It only embeds files that really are images. Because of this exception, the extension can't be distributed through the Mac App Store.

## Third-party software

- [swift-markdown](https://github.com/swiftlang/swift-markdown): Apache License 2.0
- [swift-cmark](https://github.com/swiftlang/swift-cmark) (GitHub's cmark-gfm): BSD 2-Clause License
- [highlight.js](https://highlightjs.org) 11.11.1: BSD 3-Clause License. Bundled as `MarkdownQuickLook/highlight.min.js`, with its copyright notice in the file header.

## License

BSD 3-Clause License. See [LICENSE](LICENSE). The original QLMarkdownGFM is Copyright (c) 2018, Watson.
