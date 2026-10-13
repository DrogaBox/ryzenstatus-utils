// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The island timer's phases. Kept on its own (Foundation-only) because the
/// activity strings name each phase, and the unit harness compiles those
/// strings without the timer's layout and service code.
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak, stopwatch }
