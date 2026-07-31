// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Category classification for processes.
enum ProcessCategory: String, Sendable, Codable, Equatable {
    case system
    case app
    case helper
    case background
    case developer
    case security
}

/// Information entry for a recognized process in the glossary.
struct ProcessGlossaryEntry: Sendable, Equatable {
    let name: String
    let category: ProcessCategory
    let localizedTitleKey: String
    let localizedDescriptionKey: String
}

/// Plain-language catalog explaining what system and background processes do.
enum ProcessGlossary {
    private static let entries: [ProcessGlossaryEntry] = [
        ProcessGlossaryEntry(
            name: "WindowServer",
            category: .system,
            localizedTitleKey: "glossary_windowserver_title",
            localizedDescriptionKey: "glossary_windowserver_desc"
        ),
        ProcessGlossaryEntry(
            name: "mds",
            category: .system,
            localizedTitleKey: "glossary_mds_title",
            localizedDescriptionKey: "glossary_mds_desc"
        ),
        ProcessGlossaryEntry(
            name: "cloudd",
            category: .background,
            localizedTitleKey: "glossary_cloudd_title",
            localizedDescriptionKey: "glossary_cloudd_desc"
        ),
        ProcessGlossaryEntry(
            name: "fseventsd",
            category: .system,
            localizedTitleKey: "glossary_fseventsd_title",
            localizedDescriptionKey: "glossary_fseventsd_desc"
        ),
        ProcessGlossaryEntry(
            name: "trustd",
            category: .security,
            localizedTitleKey: "glossary_trustd_title",
            localizedDescriptionKey: "glossary_trustd_desc"
        ),
        ProcessGlossaryEntry(
            name: "launchd",
            category: .system,
            localizedTitleKey: "glossary_launchd_title",
            localizedDescriptionKey: "glossary_launchd_desc"
        ),
        ProcessGlossaryEntry(
            name: "bird",
            category: .background,
            localizedTitleKey: "glossary_bird_title",
            localizedDescriptionKey: "glossary_bird_desc"
        ),
        ProcessGlossaryEntry(
            name: "sysmond",
            category: .system,
            localizedTitleKey: "glossary_sysmond_title",
            localizedDescriptionKey: "glossary_sysmond_desc"
        ),
        ProcessGlossaryEntry(
            name: "softwareupdated",
            category: .system,
            localizedTitleKey: "glossary_softwareupdated_title",
            localizedDescriptionKey: "glossary_softwareupdated_desc"
        ),
        ProcessGlossaryEntry(
            name: "logd",
            category: .system,
            localizedTitleKey: "glossary_logd_title",
            localizedDescriptionKey: "glossary_logd_desc"
        ),
        ProcessGlossaryEntry(
            name: "coreduetd",
            category: .system,
            localizedTitleKey: "glossary_coreduetd_title",
            localizedDescriptionKey: "glossary_coreduetd_desc"
        ),
        ProcessGlossaryEntry(
            name: "kernel_task",
            category: .system,
            localizedTitleKey: "glossary_kernel_task_title",
            localizedDescriptionKey: "glossary_kernel_task_desc"
        ),
        ProcessGlossaryEntry(
            name: "Dock",
            category: .system,
            localizedTitleKey: "glossary_dock_title",
            localizedDescriptionKey: "glossary_dock_desc"
        ),
        ProcessGlossaryEntry(
            name: "Finder",
            category: .system,
            localizedTitleKey: "glossary_finder_title",
            localizedDescriptionKey: "glossary_finder_desc"
        )
    ]

    /// Matches a process name against the glossary catalog.
    static func lookup(name: String) -> ProcessGlossaryEntry? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = entries.first(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            return exact
        }
        if cleanName.hasPrefix("mdworker") || cleanName.hasPrefix("mds_") {
            return entries.first(where: { $0.name == "mds" })
        }
        return nil
    }
}
