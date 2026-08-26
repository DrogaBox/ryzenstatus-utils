// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// The right-hand preview pane of the clipboard quick panel. Always shows the
/// full content of the currently selected history entry so the user can read
/// it and select any portion with the mouse before copying.
struct ClipboardEntryPreviewSidebar: View {
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var isEditing: Bool
    @State private var draft = ""
    @State private var editingEntryID: UUID?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            if let entry {
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else {
                    contentScrollView(entry)
                }
                Divider()
                sidebarFooter(entry)
            } else {
                emptyState
            }
        }
        .padding(.leading, 12)
        .onChange(of: entry?.id) { _, newID in
            if editingEntryID != nil, editingEntryID != newID {
                cancelEditing()
            }
        }
        .onDisappear { cancelEditing() }
    }

    // MARK: – Header

    private var sidebarHeader: some View {
        Text(text.previewLabel.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.bottom, 7)
    }

    // MARK: – Content

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .padding(.vertical, 10)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func textEditor(_ entry: ClipboardHistoryEntry) -> some View {
        TextEditor(text: $draft)
            .font(.system(size: 11))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            )
            .padding(.vertical, 10)
            .padding(.trailing, 4)
            .focused($editorFocused)
            .onExitCommand { cancelEditing() }
            .accessibilityLabel(text.edit)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // The full text with standard macOS selection so the user can
            // highlight any substring and press ⌘C to copy just that part.
            // ⌘C only reaches here when no batch selection is active in the
            // list (the key monitor leaves it alone in that case).
            Text(entry.text)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)

        case .image:
            imagePreview(entry)

        case .files:
            filesPreview(entry)
        }
    }

    @ViewBuilder
    private func filesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.filePaths.count == 1, let path = entry.filePaths.first {
            singleFilePreview(path)
        } else {
            multipleFilesPreview(entry)
        }
    }

    @ViewBuilder
    private func singleFilePreview(_ path: String) -> some View {
        let isImage = ClipboardImageStore.isImageFile(atPath: path)
        let thumbnail = ClipboardImageStore.fileThumbnail(atPath: path)
        let fileName = (path as NSString).lastPathComponent

        VStack(alignment: .leading, spacing: 10) {
            if isImage, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                let dim = ClipboardImageStore.imageDimensionsLabel(atPath: path)
                let size = ClipboardImageStore.fileSizeString(atPath: path)
                let parts = [text.imageEntryLabel, dim, size].compactMap { $0 }
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        if let size = ClipboardImageStore.fileSizeString(atPath: path) {
                            Text(size)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func multipleFilesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: text.fileCountFormat, entry.filePaths.count))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(entry.filePaths, id: \.self) { path in
                    HStack(spacing: 6) {
                        if ClipboardImageStore.isImageFile(atPath: path),
                           let thumb = ClipboardImageStore.fileThumbnail(atPath: path, maxPixelSize: 64) {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            Text(entry.filePaths.joined(separator: "\n"))
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }


    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.imageFile,
               let image = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: – Empty state

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Footer

    private func sidebarFooter(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.accentColor)
            }
            Text(entry.copiedAt, style: .time)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            if editingEntryID == entry.id {
                Button(text.cancel) {
                    cancelEditing()
                }
                Button(text.save) {
                    saveEditing(entry)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ClipboardHistoryEditing.canSave(original: entry.text, draft: draft))
            } else {
                if entry.kind == .text {
                    Button(text.edit) {
                        beginEditing(entry)
                    }
                }
                Button(text.copy) {
                    ClipboardHistoryService.shared.copyOnlyQuickEntry(entry)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.mini)
        .padding(.vertical, 8)
        .padding(.trailing, 4)
    }

    private func beginEditing(_ entry: ClipboardHistoryEntry) {
        draft = entry.text
        editingEntryID = entry.id
        isEditing = true
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        editingEntryID = nil
        draft = ""
        isEditing = false
    }

    private func saveEditing(_ entry: ClipboardHistoryEntry) {
        guard ClipboardHistoryService.shared.updateText(entry, to: draft) else { return }
        cancelEditing()
    }
}
