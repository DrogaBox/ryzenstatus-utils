// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit
import Combine

/// Shared state for the chooser. Every overlay panel observes the same value,
/// so changing a mode on one display updates the controls on all displays.
final class ScreenCaptureSelectionOptions: ObservableObject {
    let availableTools: [ScreenCaptureTool]
    let showsCaptureMenu: Bool
    let controlsInNotch: Bool
    var hasFocusedControl = false
    var onPresentationReady: (() -> Void)?
    var onSelectionProgressChange: ((Bool) -> Void)?
    var onCaptureControlsSurfaceChange: ((CGRect, CGFloat) -> Void)?
    let recorderAudio = RecorderSelectionAudioOptions()
    @Published private(set) var selectedTool: ScreenCaptureTool
    @Published var offersRepeatLastRegion = false
    var onSelectionChange: (() -> Void)?

    init(availableTools: [ScreenCaptureTool], selectedTool: ScreenCaptureTool,
         showsCaptureMenu: Bool, controlsInNotch: Bool = false) {
        precondition(availableTools.contains(selectedTool))
        self.availableTools = availableTools
        self.selectedTool = selectedTool
        self.showsCaptureMenu = showsCaptureMenu
        self.controlsInNotch = controlsInNotch
    }

    func select(_ tool: ScreenCaptureTool) {
        guard availableTools.contains(tool), selectedTool != tool else { return }
        selectedTool = tool
        onSelectionChange?()
    }
}
