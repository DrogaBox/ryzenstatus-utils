// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

// Keys for the wallpaper gallery, quit/close protection and the disk image
// installer. Registered values live in `Defaults.registeredDefaults`.
extension DefaultsKey {
    // Disk image installer.
    static let diskImageInstallerTrashesDownload = "diskImageInstallerTrashesDownload"
    static let diskImageInstallerRevealsApp = "diskImageInstallerRevealsApp"
    static let diskImageInstallerUseUserApplications = "diskImageInstallerUseUserApplications"

    // Quit/close protection: each shortcut owns its full configuration and app list.
    static let quitProtectionQuitEnabled = "quitProtectionQuitEnabled"
    static let quitProtectionQuitMode = "quitProtectionQuitMode"
    static let quitProtectionQuitHoldDurationMs = "quitProtectionQuitHoldDurationMs"
    static let quitProtectionQuitDoubleIntervalMs = "quitProtectionQuitDoubleIntervalMs"
    static let quitProtectionQuitExtraModifier = "quitProtectionQuitExtraModifier"
    static let quitProtectionQuitScope = "quitProtectionQuitScope"
    static let quitProtectionQuitExceptions = "quitProtectionQuitExceptions"
    static let quitProtectionQuitShowFeedback = "quitProtectionQuitShowFeedback"
    static let quitProtectionCloseEnabled = "quitProtectionCloseEnabled"
    static let quitProtectionCloseMode = "quitProtectionCloseMode"
    static let quitProtectionCloseHoldDurationMs = "quitProtectionCloseHoldDurationMs"
    static let quitProtectionCloseDoubleIntervalMs = "quitProtectionCloseDoubleIntervalMs"
    static let quitProtectionCloseExtraModifier = "quitProtectionCloseExtraModifier"
    static let quitProtectionCloseScope = "quitProtectionCloseScope"
    static let quitProtectionCloseExceptions = "quitProtectionCloseExceptions"
    static let quitProtectionCloseShowFeedback = "quitProtectionCloseShowFeedback"

    // Wallpaper gallery.
    static let panelShowWallpaper = "panelShowWallpaper"
    static let wallpaperApplyAllDisplays = "wallpaperApplyAllDisplays"
    static let wallpaperFilter = "wallpaperFilter"
    static let wallpaperOwnBookmarks = "wallpaperOwnBookmarks"
    // paths hidden from folder scans (does not delete files)
    static let wallpaperExcludedOwnPaths = "wallpaperExcludedOwnPaths"
}
