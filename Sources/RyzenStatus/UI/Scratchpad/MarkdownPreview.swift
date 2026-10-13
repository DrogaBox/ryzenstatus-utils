// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// Formats the markdown preview for Scratchpad.
/// Shared with the island's page, which shows the same formatted reading.
struct MarkdownPreview: NSViewRepresentable {
    let blocks: [ScratchpadMarkdownBlock]
    var baseSize: CGFloat = PlainTextEditor.defaultFontSize

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor]
        textView.textStorage?.setAttributedString(Self.rendered(blocks, base: baseSize))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let content = Self.rendered(blocks, base: baseSize)
        guard !textView.attributedString().isEqual(to: content) else { return }
        textView.textStorage?.setAttributedString(content)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func rendered(_ blocks: [ScratchpadMarkdownBlock],
                                 base: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let sameContainer = block.containerID != nil
                    && block.containerID == blocks[index - 1].containerID
                result.append(NSAttributedString(string: sameContainer ? "\n" : "\n\n"))
            }
            result.append(rendered(block, base: base))
        }
        return result
    }

    private static func rendered(_ block: ScratchpadMarkdownBlock,
                                 base: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        var font = NSFont.systemFont(ofSize: base)
        var color = NSColor.labelColor
        var prefix = ""
        var text = block.text
        text.presentationIntent = nil

        switch block.kind {
        case .heading(let level):
            let size: CGFloat = base + (level == 1 ? 5 : (level == 2 ? 3 : 1))
            font = .systemFont(ofSize: size, weight: .semibold)
        case .unorderedListItem(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "• "
        case .orderedListItem(let ordinal, let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "\(ordinal). "
        case .quote(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "▏ "
            color = .secondaryLabelColor
        case .code:
            font = .monospacedSystemFont(ofSize: base - 1, weight: .regular)
        case .thematicBreak:
            text = AttributedString(String(repeating: "─", count: 24))
            color = .secondaryLabelColor
        case .paragraph:
            break
        }

        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            result.append(NSAttributedString(string: prefix, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        }

        let content = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: content.length)
        content.removeAttribute(NSAttributedString.Key("NSPresentationIntent"), range: fullRange)
        content.addAttributes([
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ], range: fullRange)
        if block.kind == .code {
            content.addAttribute(.backgroundColor,
                                 value: NSColor.labelColor.withAlphaComponent(0.07),
                                 range: fullRange)
        }
        applyInlineFormatting(to: content, baseFont: font)
        result.append(content)
        return result
    }

    private static func applyInlineFormatting(to content: NSMutableAttributedString,
                                              baseFont: NSFont) {
        let fullRange = NSRange(location: 0, length: content.length)
        var intents: [(InlinePresentationIntent, NSRange)] = []
        content.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let rawValue = (value as? NSNumber)?.uintValue else { return }
            intents.append((InlinePresentationIntent(rawValue: rawValue), range))
        }

        for (intent, range) in intents {
            var font = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: max(9, baseFont.pointSize - 1), weight: .regular)
                : baseFont
            if intent.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            content.addAttribute(.font, value: font, range: range)
            if intent.contains(.code) {
                content.addAttribute(.backgroundColor,
                                     value: NSColor.labelColor.withAlphaComponent(0.07),
                                     range: range)
            }
            if intent.contains(.strikethrough) {
                content.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView,
                      clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            return NSWorkspace.shared.open(url)
        }
    }
}
