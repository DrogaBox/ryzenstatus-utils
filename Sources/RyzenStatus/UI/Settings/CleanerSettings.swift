// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

/// Settings page for the system cleaner. Wraps the existing CleanerView
/// so the feature appears in the Settings sidebar alongside the other
/// app-management tools.
struct CleanerSettings: View {
    var body: some View {
        CleanerView()
    }
}
