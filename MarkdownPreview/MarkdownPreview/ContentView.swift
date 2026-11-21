//
//  ContentView.swift
//  MarkdownPreview
//
//  Created by Benóný Egilson on 11/19/26.
//
//  The host app's only job is to install the Quick Look extension. This screen
//  tells people it worked and how to turn the extension on if previews don't show.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Text("The Quick Look extension is installed. Select a Markdown file in Finder and press Space to preview it.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If Markdown files still show as plain text:")
                        .font(.headline)
                    step(1, "Open \(Self.settingsPath).")
                    step(2, "Turn on **MarkdownQuickLook**.")
                    step(3, "Turn off any other Markdown Quick Look extension.")
                    step(4, "Close and reopen the Quick Look window.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Button("Open Extension Settings", action: openExtensionSettings)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Link("Project on GitHub", destination: URL(string: "https://github.com/BEgilson/QLMarkdownGFM")!)
            }

            Text("You can quit this app. The extension keeps working without it, as long as the app stays in your Applications folder.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("QLMarkdownGFM")
                    .font(.title)
                    .bold()
                Text("GitHub-style Markdown previews in Quick Look")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundColor(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the Quick Look extension switches live; Apple has moved them twice.
    private static var settingsPath: String {
        if #available(macOS 15, *) {
            return "System Settings → General → Login Items & Extensions → Quick Look"
        } else if #available(macOS 13, *) {
            return "System Settings → Privacy & Security → Extensions → Quick Look"
        } else {
            return "System Preferences → Extensions → Quick Look"
        }
    }

    private func openExtensionSettings() {
        let extensions = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!
        if !NSWorkspace.shared.open(extensions) {
            // Fall back to opening System Settings itself.
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

#Preview {
    ContentView()
}
