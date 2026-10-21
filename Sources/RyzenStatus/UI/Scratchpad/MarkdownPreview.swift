// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import SwiftUI

/// A selectable native preview. NSTextView keeps Markdown links interactive in
/// the nonactivating scratchpad panel, where SwiftUI's Text link handling does
/// not receive clicks reliably.
/// Shared with the island's page, which shows the same formatted reading.
struct MarkdownPreview: NSViewRepresentable {
    let blocks: [ScratchpadMarkdownBlock]
    var baseSize: CGFloat = PlainTextEditor.defaultFontSize
    /// How a task's checkbox tells VoiceOver it is done or not.
    let taskStates: (done: String, notDone: String)
    /// Called with the text offset of the box whose checkbox is clicked; the
    /// owner edits the text, and the preview follows from it.
    var onToggleTask: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        // The same text view `scrollableTextView()` makes, as the subclass that
        // answers a click on a checkbox and points its cursor at it.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = TaskPreviewTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        textView.onToggleTask = onToggleTask
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor]
        context.coordinator.show(blocks, base: baseSize, taskStates: taskStates, in: textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onToggleTask = onToggleTask
        (textView as? TaskPreviewTextView)?.onToggleTask = onToggleTask
        context.coordinator.show(blocks, base: baseSize, taskStates: taskStates, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onToggleTask = onToggleTask
        return coordinator
    }

    /// Where a list item's text starts, which is where the items nested under
    /// it start. `indented` marks an item placed by paragraph indents, a task
    /// or an item under one, rather than by the leading spaces bullets use.
    private struct ListLevel {
        let column: CGFloat
        let indented: Bool
    }

    private static func rendered(_ blocks: [ScratchpadMarkdownBlock],
                                 base: CGFloat,
                                 taskStates: (done: String, notDone: String)) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // The latest item at each depth of the list being drawn.
        var levels: [ListLevel] = []
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let sameContainer = block.containerID != nil
                    && block.containerID == blocks[index - 1].containerID
                result.append(NSAttributedString(string: sameContainer ? "\n" : "\n\n"))
                if !sameContainer { levels = [] }
            }
            result.append(rendered(block, base: base, taskStates: taskStates, levels: &levels))
        }
        return result
    }

    private static func rendered(_ block: ScratchpadMarkdownBlock,
                                 base: CGFloat,
                                 taskStates: (done: String, notDone: String),
                                 levels: inout [ListLevel]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        var font = NSFont.systemFont(ofSize: base)
        var color = NSColor.labelColor
        var prefix = ""
        var marker = ""
        var listDepth = 0
        var checkbox: (checked: Bool, box: Int)?
        let boxSize = base + 3
        var text = block.text
        text.presentationIntent = nil

        switch block.kind {
        case .heading(let level):
            // Steps above the body rather than fixed points, so the
            // document keeps its shape at whatever size the pad is set to.
            let size: CGFloat = base + (level == 1 ? 5 : (level == 2 ? 3 : 1))
            font = .systemFont(ofSize: size, weight: .semibold)
        case .unorderedListItem(let depth):
            listDepth = depth
            marker = "• "
        case .taskListItem(let depth, let checked, let box):
            listDepth = depth
            checkbox = (checked, box)
            if checked { color = .secondaryLabelColor }
        case .orderedListItem(let ordinal, let depth):
            listDepth = depth
            marker = "\(ordinal). "
        case .quote(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "▏ "
            color = .secondaryLabelColor
        case .code:
            // A point under the body, as inline code is, since monospace
            // reads larger than the system face at the same size.
            font = .monospacedSystemFont(ofSize: base - 1, weight: .regular)
        case .thematicBreak:
            text = AttributedString(String(repeating: "─", count: 24))
            color = .secondaryLabelColor
        case .paragraph:
            break
        }

        // A list inside a quote keeps the quote's bar and colour ahead of
        // its own marker.
        let quote = block.quoteDepth > 0 ? String(repeating: "  ", count: block.quoteDepth - 1) + "▏ " : ""
        if block.quoteDepth > 0 { color = .secondaryLabelColor }
        var quoteGap: CGFloat = 0
        if listDepth > 0 {
            func width(_ string: String) -> CGFloat { (string as NSString).size(withAttributes: [.font: font]).width }
            // The items above this one. A list can open below depth 1, as
            // `- - [ ] a` does; the levels it skips hold no text, so each
            // takes two spaces, as bullets do, and the item still lands at
            // its own depth for its siblings to find.
            levels = Array(levels.prefix(listDepth - 1))
            while levels.count < listDepth - 1 {
                let above = levels.last ?? ListLevel(column: width(quote), indented: false)
                levels.append(ListLevel(column: above.column + width("  "), indented: above.indented))
            }
            let parent = levels.last
            if checkbox != nil || parent?.indented == true {
                // As in Notes, a task's circle, or an item under a task, sits
                // under its parent's text, and a task's wrapped lines hang
                // under its own text rather than under the circle. A quote's
                // bar can be wider than a parent's marker, and then the item
                // starts after the bar.
                let lead = max(parent?.column ?? 0, width(quote))
                let column = lead + (checkbox != nil ? boxSize + width(" ") : width(marker))
                if quote.isEmpty { paragraph.firstLineHeadIndent = lead } else { quoteGap = lead - width(quote) }
                paragraph.headIndent = checkbox != nil ? column : lead
                prefix = quote + marker
                levels.append(ListLevel(column: column, indented: true))
            } else {
                prefix = quote + String(repeating: "  ", count: listDepth - 1) + marker
                levels.append(ListLevel(column: width(prefix), indented: false))
            }
        }

        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            result.append(NSAttributedString(string: prefix, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
            // The quote's bar stays at the line's start, so a nested item
            // in a quote reaches its column by widening the space after it.
            if quoteGap > 0 {
                result.addAttribute(.kern, value: quoteGap,
                                    range: NSRange(location: (quote as NSString).length - 1, length: 1))
            }
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
        if let checkbox {
            // The glyph is a link, so a click on it reaches the coordinator.
            let attachment = TaskBoxAttachment(checked: checkbox.checked, size: boxSize,
                                               description: checkbox.checked ? taskStates.done : taskStates.notDone)
            let box = NSMutableAttributedString(attachment: attachment)
            box.append(NSAttributedString(string: " "))
            box.addAttributes([
                .font: font,
                .paragraphStyle: paragraph,
                .link: URL(string: "\(ScratchpadSupport.taskScheme)://\(checkbox.box)") as Any
            ], range: NSRange(location: 0, length: box.length))
            result.append(box)
            if case .taskListItem(_, true, _) = block.kind {
                content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            }
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
        var onToggleTask: ((Int) -> Void)?
        /// What the reading was last drawn from. Every render makes new
        /// checkbox attachments, and two attachments never compare equal, so
        /// the drawn text cannot tell an unchanged reading from a new one;
        /// replacing it on every view update would drop its selection.
        private var shown: (blocks: [ScratchpadMarkdownBlock], base: CGFloat, done: String, notDone: String)?

        func show(_ blocks: [ScratchpadMarkdownBlock], base: CGFloat,
                  taskStates: (done: String, notDone: String), in textView: NSTextView) {
            if let shown, shown.blocks == blocks, shown.base == base,
               shown.done == taskStates.done, shown.notDone == taskStates.notDone { return }
            shown = (blocks, base, taskStates.done, taskStates.notDone)
            textView.textStorage?.setAttributedString(MarkdownPreview.rendered(blocks, base: base, taskStates: taskStates))
        }

        func textView(_ textView: NSTextView,
                      clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            if url.scheme == ScratchpadSupport.taskScheme {
                if let box = url.host.flatMap(Int.init) { onToggleTask?(box) }
                return true
            }
            return NSWorkspace.shared.open(url)
        }
    }
}

/// A task's checkbox as Notes draws its checklist: an empty ring, filled
/// with the accent colour and a check once the task is done. The system
/// colours resolve as the box is drawn, so it follows the light or dark
/// appearance, and `description` names which of the two it is.
final class TaskBoxAttachment: NSTextAttachment {
    let checked: Bool

    init(checked: Bool, size: CGFloat, description: String) {
        self.checked = checked
        super.init(data: nil, ofType: nil)
        // A palette lays a colour's alpha over the ring's own, which leaves
        // tertiary label at a faint 7%; hierarchical draws it as Notes does.
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(checked
                ? NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor])
                : NSImage.SymbolConfiguration(hierarchicalColor: .tertiaryLabelColor))
        let symbol = NSImage(systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
                             accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        image = symbol
        bounds = CGRect(x: 0, y: -(size * 0.2), width: size, height: size)
    }

    required init?(coder: NSCoder) { nil }
}

/// The preview's text view: a click on a checkbox toggles its task, and the
/// pointer over one becomes a hand, as over any button of the island.
final class TaskPreviewTextView: NSTextView {
    var onToggleTask: ((Int) -> Void)?
    private var pointerArea: NSTrackingArea?
    /// Kept while their boxes stay, so the one VoiceOver is on lives on.
    private var boxElements: [Int: BoxElement] = [:]
    /// A link element of the text view asks the view for its children to
    /// answer its own attributes, so that inner call gets the plain list.
    private var listingChildren = false

    /// A task's checkbox as VoiceOver meets it: named by its task, valued by
    /// whether it is done, and pressed as a click on it is.
    private final class BoxElement: NSAccessibilityElement {
        weak var view: TaskPreviewTextView?
        var box = 0
        var character = 0

        init(view: TaskPreviewTextView) {
            self.view = view
            super.init()
            setAccessibilityRole(.checkBox)
            setAccessibilityParent(view)
            setAccessibilityElement(true)
        }

        override func accessibilityFrame() -> NSRect {
            view?.firstRect(forCharacterRange: NSRange(location: character, length: 1), actualRange: nil) ?? .zero
        }

        override func accessibilityPerformPress() -> Bool {
            guard let toggle = view?.onToggleTask else { return false }
            toggle(box)
            return true
        }
    }

    /// The text view offers a box only as a link named by the attachment's
    /// object replacement character, so the box's link leaves the children
    /// and the box stands there as a checkbox of its own.
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren() ?? []
        guard !listingChildren, let storage = textStorage else { return children }
        listingChildren = true
        defer { listingChildren = false }
        let text = storage.string as NSString
        var boxes: [BoxElement] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? TaskBoxAttachment,
                  let url = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                  url.scheme == ScratchpadSupport.taskScheme, let box = url.host.flatMap(Int.init) else { return }
            let element = boxElements[box] ?? BoxElement(view: self)
            let line = text.paragraphRange(for: range)
            let task = NSRange(location: range.upperBound, length: line.upperBound - range.upperBound)
            element.box = box
            element.character = range.location
            element.setAccessibilityLabel(text.substring(with: task).trimmingCharacters(in: .whitespacesAndNewlines))
            element.setAccessibilityValue(attachment.checked ? 1 : 0)
            element.setAccessibilityValueDescription(attachment.image?.accessibilityDescription)
            boxes.append(element)
        }
        boxElements = Dictionary(boxes.map { ($0.box, $0) }, uniquingKeysWith: { first, _ in first })
        return children.filter {
            ($0 as? NSAccessibilityElement)?.accessibilityURL()?.scheme != ScratchpadSupport.taskScheme
        } + boxes
    }

    /// The text offset of the box whose checkbox is under `point`.
    private func taskBox(at point: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(inContainer)
        else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard let url = storage.attribute(.link, at: character, effectiveRange: nil) as? URL,
              url.scheme == ScratchpadSupport.taskScheme else { return nil }
        return url.host.flatMap(Int.init)
    }

    override func mouseDown(with event: NSEvent) {
        if let box = taskBox(at: convert(event.locationInWindow, from: nil)) {
            onToggleTask?(box)
        } else {
            super.mouseDown(with: event)
        }
    }

    /// NSTextView puts its text cursor back on every move over selectable
    /// text, past any cursor rect, so the pointer is set here instead, as the
    /// pointer moves and when it enters.
    private func pointer(for event: NSEvent) -> Bool {
        guard taskBox(at: convert(event.locationInWindow, from: nil)) != nil else { return false }
        NSCursor.pointingHand.set()
        return true
    }

    override func cursorUpdate(with event: NSEvent) {
        if !pointer(for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if !pointer(for: event) { super.mouseMoved(with: event) }
    }

    /// AppKit asks again whenever the view's geometry changes, so the area
    /// added last time goes before the next one, or they pile up and each
    /// pointer move runs the hit test once per area.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }
}
